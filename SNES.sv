//============================================================================
//  SNES for MiSTer
//  Copyright (C) 2017-2019 Srg320
//  Copyright (C) 2018-2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================ 

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS,
	
	output  wire         bridge_m0_waitrequest,
	output  wire [31:0]  bridge_m0_readdata,
	output  reg          bridge_m0_readdatavalid,
	input   wire [6:0]   bridge_m0_burstcount,
	input   wire [31:0]  bridge_m0_writedata,
	input   wire [19:0]  bridge_m0_address,
	input   wire         bridge_m0_write,
	input   wire         bridge_m0_read,
	input   wire         bridge_m0_byteenable,
	output  wire         bridge_m0_clk
);

assign ADC_BUS  = 'Z;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;

assign AUDIO_S   = 1;
assign AUDIO_MIX = status[20:19];

assign LED_USER  = cart_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;
//assign BUTTONS   = osd_btn;

assign VIDEO_ARX = status[31:30] == 2 ? 8'd16 : (status[30] ? 8'd8 : 8'd64);
assign VIDEO_ARY = status[31:30] == 2 ? 8'd9  : (status[30] ? 8'd7 : 8'd49);

//assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

///////////////////////  CLOCK/RESET  ///////////////////////////////////

wire clock_locked;
wire clk_sys;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(clock_locked)
);


wire reset = RESET | buttons[1] | status[0] | cart_download;

////////////////////////////  HPS I/O  //////////////////////////////////

// Status Bit Map:
// 0         1         2         3          4         5         6
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX 

`include "build_id.v"
parameter CONF_STR = {
    "SNES;;",
    "FS,SFCSMCBIN;",
    "-;",
    "OEF,Video Region,Auto,NTSC,PAL;",
    "O13,ROM Header,Auto,No Header,LoROM,HiROM,ExHiROM;",
    "-;",
    "C,Cheats;",
    "H2OO,Cheats Enabled,Yes,No;",
    "-;",
    "D0RC,Load Backup RAM;",
    "D0RD,Save Backup RAM;",
    "D0ON,Autosave,Off,On;",
    "D0-;",

	 "P1,Audio & Video;",
    "P1-;",
    "P1OUV,Aspect Ratio,4:3,8:7,16:9;",
    "P1O9B,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
    "P1OG,Pseudo Transparency,Blend,Off;",
    "P1-;",
    "P1OJK,Stereo Mix,None,25%,50%,100%;", 

	 "P2,Hardware;",
    "P2-;",
    "P2OH,Multitap,Disabled,Port2;",
    "P2O8,Serial,OFF,SNAC;",
    "P2-;",
    "P2OPQ,Super Scope,Disabled,Joy1,Joy2,Mouse;",
    "D4P2OR,Super Scope Btn,Joy,Mouse;",
    "D4P2OST,Cross,Small,Big,None;",
    "P2-;",
    "D1P2OI,SuperFX Speed,Normal,Turbo;",
    "D3P2O4,CPU Speed,Normal,Turbo;",
    "P2-;",
    "P2OLM,Initial WRAM,9966(SNES2),00FF(SNES1),55(SD2SNES),FF;",

    "-;",
    "O56,Mouse,None,Port1,Port2;",
    "O7,Swap Joysticks,No,Yes;",
    "-;",
    "R0,Reset;",
    "J1,A(SS Fire),B(SS Cursor),X(SS TurboSw),Y(SS Pause),LT(SS Cursor),RT(SS Fire),Select,Start;",
    "V,v",`BUILD_DATE
};

wire  [1:0] buttons;
wire [63:0] status;
//wire [15:0] status_menumask = {!GUN_MODE, ~turbo_allow, ~gg_available, ~GSU_ACTIVE, ~bk_ena};
wire [15:0] status_menumask = 16'h0000;
wire        forced_scandoubler;
reg  [31:0] sd_lba;
reg         sd_rd = 0;
reg         sd_wr = 0;
wire        sd_ack;
wire  [7:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire        ioctl_download;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_wr;
wire  [7:0] ioctl_index;

wire [11:0] joy0,joy1,joy2,joy3,joy4;
wire [24:0] ps2_mouse;

wire  [7:0] joy0_x,joy0_y,joy1_x,joy1_y;

wire [64:0] RTC;

wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.conf_str(CONF_STR),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),
	.new_vmode(new_vmode),

	.joystick_analog_0({joy0_y, joy0_x}),
	.joystick_analog_1({joy1_y, joy1_x}),
	.joystick_0(joy0),
	.joystick_1(joy1),
	.joystick_2(joy2),
	.joystick_3(joy3),
	.joystick_4(joy4),
	.ps2_mouse(ps2_mouse),

	.status(status),
	.status_menumask(status_menumask),
	.status_in({status[63:5],1'b0,status[3:0]}),
	.status_set(cart_download),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr(ioctl_wr),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	
	.RTC(RTC),

	.gamma_bus(gamma_bus)
);

gpu gpu_inst
(
	.clk( clk_sys ) ,					// input  clk
	.i_nrst( !reset & gpu_nrst ) ,// input  i_nrst
	
	.IRQRequest( IRQRequest ) ,	// output  IRQRequest
	
	.DMA_REQ( DMA_REQ ) ,			// output  DMA_REQ
	.DMA_ACK( DMA_ACK ) ,			// input  DMA_ACK
	
	.mydebugCnt(mydebugCnt) ,		// output [31:0] mydebugCnt
	.dbg_canWrite(dbg_canWrite) ,	// output  dbg_canWrite
	
	.clkBus( clk_sys ) ,				// input  clkBus
	
	.o_command(o_command) ,			// output  o_command
	.i_busy(i_busy) ,					// input  i_busy
	.o_commandSize(o_commandSize) ,	// output [1:0] o_commandSize
	.o_write(o_write) ,				// output  o_write
	.o_adr(o_adr) ,					// output [14:0] o_adr
	.o_subadr(o_subadr) ,			// output [2:0] o_subadr
	.o_writeMask(o_writeMask) ,	// output [15:0] o_writeMask
	.i_dataIn(i_dataIn) ,			// input [255:0] i_dataIn
	.i_dataInValid(i_dataInValid) ,	// input  i_dataInValid
	.o_dataOut(o_dataOut) ,			// output [255:0] o_dataOut
	
	.gpuAdrA2(gpuAdrA2) ,			// input  gpuAdrA2
	.gpuSel(gpuSel) ,					// input  gpuSel
	.write(gpu_write) ,				// input  write
	.read(gpu_read) ,					// input  read
	.cpuDataIn(cpuDataIn) ,			// input [31:0] cpuDataIn
	.cpuDataOut(cpuDataOut) ,		// output [31:0] cpuDataOut
	.validDataOut(validDataOut) 	// output  validDataOut
);

wire IRQRequest;
wire DMA_REQ;
reg DMA_ACK;

reg gpu_nrst;

wire [31:0] mydebugCnt;
wire dbg_canWrite;

wire o_command;
wire i_busy = o_busyClient;
wire [1:0] o_commandSize;
wire o_write;
wire [14:0] o_adr;
wire [2:0] o_subadr;
wire [15:0] o_writeMask;
wire [255:0] i_dataIn = o_dataClient;
wire i_dataInValid = o_dataValidClient;
wire [255:0] o_dataOut;

reg gpuAdrA2;
reg gpuSel;
reg gpu_write;
reg gpu_read;
reg [31:0] cpuDataIn;
wire [31:0] cpuDataOut;
wire validDataOut;


//.bridge_m0_burstcount( bridge_m0_burstcount ) ,	// input [6:0] bridge_m0_burstcount
//.bridge_m0_writedata( bridge_m0_writedata ) ,	// input [31:0] bridge_m0_writedata
//.bridge_m0_address( bridge_m0_address ) ,			// input [19:0] bridge_m0_address
//.bridge_m0_write( bridge_m0_write ) ,				// input  bridge_m0_write
//.bridge_m0_read( bridge_m0_read ) ,					// input  bridge_m0_read
//.bridge_m0_byteenable( bridge_m0_byteenable ) ,	// input  bridge_m0_byteenable


assign bridge_m0_clk = clk_sys;						// output  bridge_m0_clk

wire [31:0] flag_data = {dbg_canWrite, IRQRequest, DMA_REQ, mydebugCnt[27:0] };

assign bridge_m0_readdata = (bridge_m0_address[3:0]==4'h8) ? flag_data : cpuDataOut;		// output [31:0] bridge_m0_readdata


reg axi_wait;
assign bridge_m0_waitrequest = axi_wait;

reg axi_readvalid;
assign bridge_m0_readdatavalid = axi_readvalid;


(*noprune*) reg [7:0] cmd_state;

always @(posedge clk_sys or posedge reset)
if (reset) begin
	gpuAdrA2 = 1'b0;
	gpuSel = 1'b0;
	gpu_write = 1'b0;
	gpu_read = 1'b0;
	cpuDataIn = 32'h00000000;
	
	cmd_state <= 8'd0;
	
	axi_wait <= 1'b1;
	axi_readvalid <= 1'b0;
	
	DMA_ACK <= 1'b0;
	
	gpu_nrst <= 1'b1;	// Start with the GPU running.
end
else begin
	case (cmd_state)
		0: begin
			axi_wait <= 1'b0;
			axi_readvalid <= 1'b0;
			
			gpuSel <= 1'b0;
			gpu_write <= 1'b0;
			gpu_read <= 1'b0;
			DMA_ACK <= 1'b0;
			
			if (bridge_m0_write) begin
				case (bridge_m0_address[3:0])
					4'h0: begin						// Write to GP0.
						gpuAdrA2 <= 1'b0;
						cpuDataIn <= bridge_m0_writedata[31:0];
						gpuSel <= 1'b1;
						gpu_write <= 1'b1;
						gpu_read <= 1'b0;
						axi_wait <= 1'b1;
						cmd_state <= 1;
					end

					4'h4: begin						// Write to GP1.
						gpuAdrA2 <= 1'b1;
						cpuDataIn <= bridge_m0_writedata[31:0];
						gpuSel <= 1'b1;
						gpu_write <= 1'b1;
						gpu_read <= 1'b0;
						axi_wait <= 1'b1;
						cmd_state <= 1;
					end

					4'h8: begin						// Write to Flags / Debug.
						gpuAdrA2 <= 1'b0;
						gpuSel <= 1'b0;			// No GPU write!
						gpu_write <= 1'b0;
						gpu_read <= 1'b0;
						DMA_ACK <= bridge_m0_writedata[31];
						gpu_nrst <= bridge_m0_writedata[30];
						axi_wait <= 1'b1;
						cmd_state <= 1;
					end

					4'hC: begin						// Write to cpuDataIn + DMA_ACK high.
						gpuAdrA2 <= 1'b0;
						gpuSel <= 1'b0;			// Don't think gpuSel is required?
						gpu_write <= 1'b1;
						gpu_read <= 1'b0;
						DMA_ACK <= 1'b1;
						axi_wait <= 1'b1;
						cmd_state <= 1;
					end

					default:;
				endcase
			end
			else if (bridge_m0_read) begin
				case (bridge_m0_address[3:0])
					4'h0: begin						// Read from GP0.
						gpuAdrA2 <= 1'b0;
						gpuSel <= 1'b1;
						gpu_write <= 1'b0;
						gpu_read <= 1'b1;
						axi_wait <= 1'b1;
						cmd_state <= 2;
					end

					4'h4: begin						// Read from GP1.
						gpuAdrA2 <= 1'b1;
						gpuSel <= 1'b1;
						gpu_write <= 1'b0;
						gpu_read <= 1'b1;
						axi_wait <= 1'b1;
						cmd_state <= 2;
					end

					4'h8: begin						// Read from Flags / Debug, without GPU select signals.
						axi_readvalid <= 1'b1;	// Pulse High for one clock (no wait for validDataOut).
						axi_wait <= 1'b0;			// Need to assert this before returning to state 0!
						cmd_state <= 0;
					end

					4'hC: begin						// Read from cpuDataOut, without GPU select signals (for DMA).
						axi_readvalid <= 1'b1;	// Pulse High for one clock (no wait for validDataOut).
						axi_wait <= 1'b0;			// Need to assert this before returning to state 0!
						cmd_state <= 0;
					end

					default:;
				endcase
			end
		end
		
		// Write
		1: begin
			gpuSel <= 1'b0;
			gpu_write <= 1'b0;
			gpu_read <= 1'b0;
			DMA_ACK <= 1'b0;
			axi_wait <= 1'b0;		// Need to assert this before returning to state 0!
			cmd_state <= 0;		// (to handle cases when axi_read or axi_write are held high.)
		end
		
		
		// Read...
		2: begin
			gpuSel <= 1'b0;
			gpu_write <= 1'b0;
			gpu_read <= 1'b0;
			DMA_ACK <= 1'b0;
			
			if (validDataOut) begin
				axi_readvalid <= 1'b1;
				axi_wait <= 1'b0;		// Need to assert this before returning to state 0!
				cmd_state <= 0;		// (to handle cases when axi_read or axi_write are held high.)
			end
		end
	
		default: ;
	endcase
end


wire i_command = o_command;
wire i_writeElseRead = o_write;
wire [1:0] i_commandSize = o_commandSize;
wire [14:0] i_targetAddr = o_adr;
wire [2:0] i_subAddr = o_subadr;
wire [15:0] i_writeMask = o_writeMask;
wire [255:0] i_dataClient = o_dataOut;

wire o_busyClient;
wire o_dataValidClient;
wire [255:0] o_dataClient;

PSX_DDR_Interface PSX_DDR_Interface_inst
(
	.i_clk( clk_sys ) ,						// input  i_clk
	.i_rst( !reset ) ,						// input  i_rst
	
	.i_command(i_command) ,					// input  i_command
	.i_writeElseRead(i_writeElseRead) ,	// input  i_writeElseRead
	.i_commandSize(i_commandSize) ,		// input [1:0] i_commandSize
	.i_targetAddr(i_targetAddr) ,			// input [14:0] i_targetAddr
	.i_subAddr(i_subAddr) ,					// input [2:0] i_subAddr
	.i_writeMask(i_writeMask) ,			// input [15:0] i_writeMask
	.i_dataClient(i_dataClient) ,			// input [255:0] i_dataClient
	.o_busyClient(o_busyClient) ,			// output  o_busyClient
	.o_dataValidClient(o_dataValidClient) ,	// output  o_dataValidClient
	.o_dataClient(o_dataClient) ,			// output [255:0] o_dataClient
	
	.i_busyMem(i_busyMem) ,					// input  i_busyMem
	.i_dataValidMem(i_dataValidMem) ,	// input  i_dataValidMem
	.i_dataMem(i_dataMem) ,					// input [31:0] i_dataMem
	.o_writeEnableMem(o_writeEnableMem) ,	// output  o_writeEnableMem
	.o_readEnableMem(o_readEnableMem) ,	// output  o_readEnableMem
	.o_burstLength(o_burstLength) ,		// output [7:0] o_burstLength
	.o_dataMem(o_dataMem) ,					// output [31:0] o_dataMem
	.o_targetAddr(o_targetAddr) ,			// output [25:0] o_targetAddr
	.o_byteEnableMem(o_byteEnableMem) 	// output [3:0] o_byteEnableMem
);

wire i_busyMem = DDRAM_BUSY;
wire i_dataValidMem = DDRAM_DOUT_READY;
wire [31:0] i_dataMem = DDRAM_DOUT[31:0];	// Note: DDRAM_DOUT is 64-bit.
wire o_writeEnableMem;
wire o_readEnableMem;
wire [7:0] o_burstLength;
wire [31:0] o_dataMem;
wire [25:0] o_targetAddr;
wire [3:0] o_byteEnableMem;

// From the core TO the Altera DDR controller...
assign DDRAM_CLK = clk_sys;
assign DDRAM_BURSTCNT = o_burstLength;					// (from the core TO DDR).

//assign DDRAM_ADDR = {3'b001, o_targetAddr[24:0] };	// This should map the GPU Framebuffer at 0x10000000 in DDR (BYTE address!).
assign DDRAM_ADDR = {3'b001, o_targetAddr[24:1],1'b0};	// This should map the GPU Framebuffer at 0x10000000 in DDR (BYTE address!).

assign DDRAM_DIN = !o_targetAddr[0] ? {32'h00000000, o_dataMem}  : {o_dataMem, 32'h00000000};	// Note: DDRAM_DIN is 64-bit.
assign DDRAM_BE  = !o_targetAddr[0] ? {4'b0000, o_byteEnableMem} : {o_byteEnableMem, 4'b0000};	// Note: DDRAM_BE has 8 bits.
assign DDRAM_WE  = o_writeEnableMem;
assign DDRAM_RD  = o_readEnableMem;

reg RESET_N = 0;
reg RFSH = 0;
always @(posedge clk_sys) begin
	reg [1:0] div;
	
	div <= div + 1'd1;
	RFSH <= !div;
	
	if (div == 2) RESET_N <= ~reset;
end

/*
////////////////////////////  CODES  ///////////////////////////////////

reg [128:0] gg_code;
wire gg_available;

// Code layout:
// {clock bit, code flags,     32'b address, 32'b compare, 32'b replace}
//  128        127:96          95:64         63:32         31:0
// Integer values are in BIG endian byte order, so it up to the loader
// or generator of the code to re-arrange them correctly.

always_ff @(posedge clk_sys) begin
	gg_code[128] <= 0;

	if (code_download & ioctl_wr) begin
		case (ioctl_addr[3:0])
			0:  gg_code[111:96]  <= ioctl_dout; // Flags Bottom Word
			2:  gg_code[127:112] <= ioctl_dout; // Flags Top Word
			4:  gg_code[79:64]   <= ioctl_dout; // Address Bottom Word
			6:  gg_code[95:80]   <= ioctl_dout; // Address Top Word
			8:  gg_code[47:32]   <= ioctl_dout; // Compare Bottom Word
			10: gg_code[63:48]   <= ioctl_dout; // Compare top Word
			12: gg_code[15:0]    <= ioctl_dout; // Replace Bottom Word
			14: begin
				gg_code[31:16]    <= ioctl_dout; // Replace Top Word
				gg_code[128]      <= 1;          // Clock it in
			end
		endcase
	end
end

////////////////////////////  MEMORY  ///////////////////////////////////

reg [16:0] mem_fill_addr;
reg clearing_ram = 0;
always @(posedge clk_sys) begin
	if(~old_downloading & cart_download)
		clearing_ram <= 1'b1;

	if (&mem_fill_addr) clearing_ram <= 0;

	if (clearing_ram)
		mem_fill_addr <= mem_fill_addr + 1'b1;
	else
		mem_fill_addr <= 0;
end

reg [7:0] wram_fill_data;
always @* begin
    case(status[22:21])
        0: wram_fill_data = (mem_fill_addr[8] ^ mem_fill_addr[2]) ? 8'h66 : 8'h99;
        1: wram_fill_data = (mem_fill_addr[9] ^ mem_fill_addr[0]) ? 8'hFF : 8'h00;
        2: wram_fill_data = 8'h55;
        3: wram_fill_data = 8'hFF;
    endcase
end

wire[23:0] ROM_ADDR;
wire       ROM_OE_N;
wire       ROM_WORD;
wire[15:0] ROM_Q;

sdram sdram
(
	.*,
	.init(0), //~clock_locked),
	.clk(clk_mem),
	
	.addr(cart_download ? ioctl_addr-10'd512 : ROM_ADDR),
	.din(ioctl_dout),
	.dout(ROM_Q),
	.rd(~cart_download & (RESET_N ? ~ROM_OE_N : RFSH)),
	.wr(ioctl_wr & cart_download),
	.word(cart_download | ROM_WORD),
	.busy()
);

wire[16:0] WRAM_ADDR;
wire       WRAM_CE_N;
wire       WRAM_WE_N;
wire [7:0] WRAM_Q, WRAM_D;
dpram #(17)	wram
(
	.clock(clk_sys),
	.address_a(WRAM_ADDR),
	.data_a(WRAM_D),
	.wren_a(~WRAM_CE_N & ~WRAM_WE_N),
	.q_a(WRAM_Q),

	// clear the RAM on loading
	.address_b(mem_fill_addr[16:0]),
	.data_b(wram_fill_data),
	.wren_b(clearing_ram)
);

wire [15:0] VRAM1_ADDR;
wire        VRAM1_WE_N;
wire  [7:0] VRAM1_D, VRAM1_Q;
dpram #(15)	vram1
(
	.clock(clk_sys),
	.address_a(VRAM1_ADDR[14:0]),
	.data_a(VRAM1_D),
	.wren_a(~VRAM1_WE_N),
	.q_a(VRAM1_Q),

	// clear the RAM on loading
	.address_b(mem_fill_addr[14:0]),
	.wren_b(clearing_ram)
);

wire [15:0] VRAM2_ADDR;
wire        VRAM2_WE_N;
wire  [7:0] VRAM2_D, VRAM2_Q;
dpram #(15) vram2
(
	.clock(clk_sys),
	.address_a(VRAM2_ADDR[14:0]),
	.data_a(VRAM2_D),
	.wren_a(~VRAM2_WE_N),
	.q_a(VRAM2_Q),

	// clear the RAM on loading
	.address_b(mem_fill_addr[14:0]),
	.wren_b(clearing_ram)
);

wire [15:0] ARAM_ADDR;
wire        ARAM_CE_N;
wire        ARAM_WE_N;
wire  [7:0] ARAM_Q, ARAM_D;
dpram #(16) aram
(
	.clock(clk_sys),
	.address_a(ARAM_ADDR),
	.data_a(ARAM_D),
	.wren_a(~ARAM_CE_N & ~ARAM_WE_N),
	.q_A(ARAM_Q),

	// clear the RAM on loading
	.address_b(mem_fill_addr[15:0]),
	.wren_b(clearing_ram)
);

localparam  BSRAM_BITS = 17; // 1Mbits
wire [19:0] BSRAM_ADDR;
wire        BSRAM_CE_N;
wire        BSRAM_WE_N;
wire  [7:0] BSRAM_Q, BSRAM_D;
dpram_dif #(BSRAM_BITS,8,BSRAM_BITS-1,16) bsram 
(
	.clock(clk_sys),

	//Thrash the BSRAM upon ROM loading
	.address_a(clearing_ram ? mem_fill_addr[BSRAM_BITS-1:0] : BSRAM_ADDR[BSRAM_BITS-1:0]),
	.data_a(clearing_ram ? 8'hFF : BSRAM_D),
	.wren_a(clearing_ram ? 1'b1 : ~BSRAM_CE_N & ~BSRAM_WE_N),
	.q_a(BSRAM_Q),

	.address_b({sd_lba[BSRAM_BITS-10:0],sd_buff_addr}),
	.data_b(sd_buff_dout),
	.wren_b(sd_buff_wr & sd_ack),
	.q_b(sd_buff_din)
);


////////////////////////////  VIDEO  ////////////////////////////////////

wire [7:0] R,G,B;
wire FIELD,INTERLACE;
wire HSync, HSYNC;
wire VSync, VSYNC;
wire HBlank_n;
wire VBlank_n;
wire HIGH_RES;
wire DOTCLK;

reg interlace;
reg ce_pix;
always @(posedge CLK_VIDEO) begin
	reg [2:0] pcnt;
	reg old_vsync;
	reg tmp_hres, frame_hres;
	reg old_dotclk;
	
	tmp_hres <= tmp_hres | HIGH_RES;

	old_vsync <= VSync;
	if(~old_vsync & VSync) begin
		frame_hres <= tmp_hres | ~scandoubler;
		tmp_hres <= HIGH_RES;
		interlace <= INTERLACE;
	end

	pcnt <= pcnt + 1'd1;
	old_dotclk <= DOTCLK;
	if(~old_dotclk & DOTCLK & HBlank_n & VBlank_n) pcnt <= 1;

	ce_pix <= !pcnt[1:0] & (frame_hres | ~pcnt[2]);
	
	if(pcnt==3) {HSync, VSync} <= {HSYNC, VSYNC};
end
*/

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL = 1'b1;

reg [9:0] hcnt;
reg [8:0] vcnt;	// Counts from 0 to 511.
always @(posedge CLK_VIDEO) begin
	if (hcnt==10'd767) begin
		hcnt <= 10'd0;
		vcnt <= vcnt + 1;
	end
	else hcnt <= hcnt + 10'd1;
end

assign VGA_HS = (hcnt[9:4]==6'd45);
assign VGA_VS = (vcnt>=9'd500 && vcnt<=9'd506);

assign VGA_R = hcnt[7:0] ^ vcnt[8:1];
assign VGA_G = hcnt[8:1] ^ vcnt[7:0];
assign VGA_B = hcnt[9:2] ^ vcnt[8:1];

assign VGA_DE = (hcnt<10'd640 && vcnt<9'd480);

assign VGA_F1 = 1'b0;
assign VGA_SL = 2'd0;


/*
assign VGA_F1 = interlace & FIELD;
assign VGA_SL = {~interlace,~interlace}&sl[1:0];

wire [2:0] scale = status[11:9];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;
wire       scandoubler = ~interlace && (scale || forced_scandoubler);
wire       scandoubler = 1'b1 && (scale || forced_scandoubler);

video_mixer #(.LINE_LENGTH(520), .GAMMA(1)) video_mixer
(
	.*,

	.clk_vid(CLK_VIDEO),
	.ce_pix_out(CE_PIXEL),

	.scanlines(0),
	.hq2x(scale==1),
	.mono(0),

	.HBlank(~HBlank_n),
	.VBlank(~VBlank_n),
	.R((LG_TARGET && GUN_MODE && (!status[29] | LG_T)) ? {8{LG_TARGET[0]}} : R),
	.G((LG_TARGET && GUN_MODE && (!status[29] | LG_T)) ? {8{LG_TARGET[1]}} : G),
	.B((LG_TARGET && GUN_MODE && (!status[29] | LG_T)) ? {8{LG_TARGET[2]}} : B)
);
*/

 
endmodule