`ifndef DRAM_SV
`define DRAM_SV

// ============================================================
//  DRAM（Data RAM）8KB
//  地址空间：0x80004000 ~ 0x80005FFF
//  2048 个 32-bit 字，word 索引 = addr[12:2]
//
//  端口：
//    数据端口（CPU MEM）：同步读 + 同步写（字节使能）
//    调试端口（DM SBA）：同步读 + 同步写（字节使能）
//
//  `ifdef SYNTHESIS：直接例化 4 × Gowin SDPB 原语
//  `else            ：行为模型（仿真用，同步读）
// ============================================================
module DRAM (
    input  wire        clk,

    // 数据端口（来自 CPU MEM，同步读 + 同步写）
    input  wire [31:0] daddr,
    input  wire        dren,
    input  wire        dwen,
    input  wire [3:0]  dbe,
    input  wire [31:0] dwdata,
    output reg  [31:0] drdata,

    // 调试端口（来自 DebugModule SBA，同步读 + 同步写）
    input  wire [31:0] dbg_addr,
    input  wire        dbg_ren,
    input  wire        dbg_wen,
    input  wire [3:0]  dbg_be,
    input  wire [31:0] dbg_wdata,
    output reg  [31:0] dbg_rdata
);

`ifdef SYNTHESIS

// ============================================================
//  综合路径：直接例化 4 × SDPB（Gowin BSRAM 原语）
//  BIT_WIDTH_0（写） = 32，BIT_WIDTH_1（读） = 32
//  每块 512 字：bank 选择 = {1'b0, word_addr[10:9]}（4 bank）
//  ADA[13:0]={word_addr[8:0], 1'b0, be[3:0]}
//  ADB[13:0]={word_addr[8:0], 5'b0}
// ============================================================

// 写端口：dbg_wen 优先
wire        wr_wen    = dbg_wen   | dwen;
wire [3:0]  wr_be     = dbg_wen   ? dbg_be    : dbe;
wire [31:0] wr_wdata  = dbg_wen   ? dbg_wdata : dwdata;
wire [31:0] wr_addr   = dbg_wen   ? dbg_addr  : daddr;

wire [10:0] wr_waddr11 = wr_addr[12:2];
wire [2:0]  wr_blksel  = {1'b0, wr_waddr11[10:9]};
wire [8:0]  wr_row     = wr_waddr11[8:0];
wire [13:0] wr_addra   = {wr_row, 1'b0, wr_be};

// 读端口：dbg_ren 优先
wire        rd_use_dbg  = dbg_ren;
wire [31:0] rd_addr     = rd_use_dbg ? dbg_addr : daddr;
wire [10:0] rd_waddr11  = rd_addr[12:2];
wire [2:0]  rd_blksel   = {1'b0, rd_waddr11[10:9]};
wire [8:0]  rd_row      = rd_waddr11[8:0];
wire [13:0] rd_addrb    = {rd_row, 5'b0};

// 延迟 1 周期的控制信号（对齐同步读输出）
reg [2:0] rd_blksel_d1;
reg       rd_use_dbg_d1;
always @(posedge clk) begin
    rd_blksel_d1  <= rd_blksel;
    rd_use_dbg_d1 <= rd_use_dbg;
end

wire [31:0] bdo [0:3];

genvar gi;
generate
for (gi = 0; gi < 4; gi = gi + 1) begin : gen_sdpb
    SDPB #(
        .READ_MODE(1'b0),
        .BIT_WIDTH_0(32),
        .BIT_WIDTH_1(32),
        .BLK_SEL_0(gi[2:0]),
        .BLK_SEL_1(gi[2:0]),
        .RESET_MODE("SYNC"),
        .INIT_RAM_00(256'h0), .INIT_RAM_01(256'h0), .INIT_RAM_02(256'h0), .INIT_RAM_03(256'h0),
        .INIT_RAM_04(256'h0), .INIT_RAM_05(256'h0), .INIT_RAM_06(256'h0), .INIT_RAM_07(256'h0),
        .INIT_RAM_08(256'h0), .INIT_RAM_09(256'h0), .INIT_RAM_0A(256'h0), .INIT_RAM_0B(256'h0),
        .INIT_RAM_0C(256'h0), .INIT_RAM_0D(256'h0), .INIT_RAM_0E(256'h0), .INIT_RAM_0F(256'h0),
        .INIT_RAM_10(256'h0), .INIT_RAM_11(256'h0), .INIT_RAM_12(256'h0), .INIT_RAM_13(256'h0),
        .INIT_RAM_14(256'h0), .INIT_RAM_15(256'h0), .INIT_RAM_16(256'h0), .INIT_RAM_17(256'h0),
        .INIT_RAM_18(256'h0), .INIT_RAM_19(256'h0), .INIT_RAM_1A(256'h0), .INIT_RAM_1B(256'h0),
        .INIT_RAM_1C(256'h0), .INIT_RAM_1D(256'h0), .INIT_RAM_1E(256'h0), .INIT_RAM_1F(256'h0),
        .INIT_RAM_20(256'h0), .INIT_RAM_21(256'h0), .INIT_RAM_22(256'h0), .INIT_RAM_23(256'h0),
        .INIT_RAM_24(256'h0), .INIT_RAM_25(256'h0), .INIT_RAM_26(256'h0), .INIT_RAM_27(256'h0),
        .INIT_RAM_28(256'h0), .INIT_RAM_29(256'h0), .INIT_RAM_2A(256'h0), .INIT_RAM_2B(256'h0),
        .INIT_RAM_2C(256'h0), .INIT_RAM_2D(256'h0), .INIT_RAM_2E(256'h0), .INIT_RAM_2F(256'h0),
        .INIT_RAM_30(256'h0), .INIT_RAM_31(256'h0), .INIT_RAM_32(256'h0), .INIT_RAM_33(256'h0),
        .INIT_RAM_34(256'h0), .INIT_RAM_35(256'h0), .INIT_RAM_36(256'h0), .INIT_RAM_37(256'h0),
        .INIT_RAM_38(256'h0), .INIT_RAM_39(256'h0), .INIT_RAM_3A(256'h0), .INIT_RAM_3B(256'h0),
        .INIT_RAM_3C(256'h0), .INIT_RAM_3D(256'h0), .INIT_RAM_3E(256'h0), .INIT_RAM_3F(256'h0)
    ) u_sdpb (
        .CLKA   (clk),
        .RESETA (1'b0),
        .CEA    (wr_wen & (wr_blksel == gi[2:0])),
        .ADA    (wr_addra),
        .DI     (wr_wdata),
        .BLKSELA(wr_blksel),
        .CLKB   (clk),
        .RESETB (1'b0),
        .CEB    (1'b1),
        .OCE    (1'b1),
        .ADB    (rd_addrb),
        .DO     (bdo[gi]),
        .BLKSELB(rd_blksel)
    );
end
endgenerate

// 同步读输出 mux（使用延迟后的控制信号）
always @(posedge clk) begin
    drdata    <= bdo[rd_blksel_d1];
    dbg_rdata <= bdo[rd_blksel_d1];
end

`else

// ============================================================
//  仿真路径：行为模型（组合读，与 Phase 1 行为一致）
// ============================================================
reg [31:0] mem [0:2047];

wire [10:0] daddr_idx    = daddr[12:2];
wire [10:0] dbg_addr_idx = dbg_addr[12:2];

// 组合读
always @(*) begin
    drdata    = mem[daddr_idx];
    dbg_rdata = mem[dbg_addr_idx];
end

// 数据端口同步写（字节使能）
always @(posedge clk) begin
    if (dwen) begin
        if (dbe[0]) mem[daddr_idx][ 7: 0] <= dwdata[ 7: 0];
        if (dbe[1]) mem[daddr_idx][15: 8] <= dwdata[15: 8];
        if (dbe[2]) mem[daddr_idx][23:16] <= dwdata[23:16];
        if (dbe[3]) mem[daddr_idx][31:24] <= dwdata[31:24];
    end
end

// 调试端口同步写（字节使能）
always @(posedge clk) begin
    if (dbg_wen) begin
        if (dbg_be[0]) mem[dbg_addr_idx][ 7: 0] <= dbg_wdata[ 7: 0];
        if (dbg_be[1]) mem[dbg_addr_idx][15: 8] <= dbg_wdata[15: 8];
        if (dbg_be[2]) mem[dbg_addr_idx][23:16] <= dbg_wdata[23:16];
        if (dbg_be[3]) mem[dbg_addr_idx][31:24] <= dbg_wdata[31:24];
    end
end

// 初始全零
integer i;
initial begin
    for (i = 0; i < 2048; i = i + 1)
        mem[i] = 32'h0000_0000;
end

`endif // SYNTHESIS

endmodule

`endif // DRAM_SV
