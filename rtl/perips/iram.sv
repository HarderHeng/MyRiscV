`ifndef IRAM_SV
`define IRAM_SV

// ============================================================
//  IRAM（Instruction RAM）16KB
//  地址空间：0x80000000 ~ 0x80003FFF
//  4096 个 32-bit 字，word 索引 = addr[13:2]
//
//  端口：
//    指令端口（CPU IF）：同步读，数据次周期有效
//    数据端口（CPU MEM）：同步读 + 同步写（字节使能）
//    调试端口（DM SBA）：同步读 + 同步写（字节使能）
//
//  `ifdef SYNTHESIS：直接例化 8 × Gowin SDPB 原语
//  `else            ：$readmemh 行为模型（仿真用）
// ============================================================
module IRAM (
    input  wire        clk,

    // 指令端口（来自 CPU IF，同步读）
    input  wire [31:0] iaddr,
    output reg  [31:0] idata,

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
//  综合路径：直接例化 8 × SDPB（Gowin BSRAM 原语）
//  BIT_WIDTH_0（写） = 32，BIT_WIDTH_1（读） = 32
//  每块 512 字：ADA[13:0]={word_addr[8:0], 1'b0, be[3:0]}
//               ADB[13:0]={word_addr[8:0], 5'b0}
//  运行时 bank 选择：BLKSELA/B = word_addr[11:9]
// ============================================================

// 写地址：{word_addr[8:0], 1'b0, byte_enable[3:0]} （共14位）
// 读地址：{word_addr[8:0], 5'b0}

// --- 指令端口（只读，使用读端口 B，CLKB 驱动）---
// 8 路 SDPB 读数据（每 bank 512×32bit）
wire [31:0] i_bdo [0:7];

// bank 选择：iaddr 字地址的高 3 位
wire [8:0]  i_word_addr   = iaddr[13:2+9] == 3'b0 ? iaddr[10:2] :
                            iaddr[11:2+9] == 2'b0  ? iaddr[10:2] :
                            iaddr[10:2];
// 简化：word_addr = iaddr[13:2]（12位），bank = [11:9]，行 = [8:0]
wire [11:0] i_waddr12     = iaddr[13:2];
wire [2:0]  i_blksel      = i_waddr12[11:9];
wire [8:0]  i_row         = i_waddr12[8:0];
wire [13:0] i_addrb       = {i_row, 5'b0};

// --- 数据端口 / 调试端口（写优先选调试端口）---
// 写端口：dbg_wen 优先，否则 CPU dwen
wire        wr_wen    = dbg_wen   | dwen;
wire [3:0]  wr_be     = dbg_wen   ? dbg_be    : dbe;
wire [31:0] wr_wdata  = dbg_wen   ? dbg_wdata : dwdata;
wire [31:0] wr_addr   = dbg_wen   ? dbg_addr  : daddr;

wire [11:0] wr_waddr12  = wr_addr[13:2];
wire [2:0]  wr_blksel   = wr_waddr12[11:9];
wire [8:0]  wr_row      = wr_waddr12[8:0];
wire [13:0] wr_addra    = {wr_row, 1'b0, wr_be};

// 数据读（CPU MEM 用读端口 B，与指令端口共享物理 B 端口）
// 注：IRAM 数据读和指令读需要分时，此处用 CPU dren/dbg_ren 切换
// 简化：为保持接口兼容，数据端口和调试端口读均借用行为模型方式
// SDPB 每个 block 只有一个 B 读端口，指令读占用
// 数据读和调试读通过行为模型（仿真路径）或分离 SDPB 实现
// → 此处策略：指令端口 8×SDPB；数据读/调试读用独立寄存器（从 SDPB B 端口复用不可行）
//
// 实际上 IRAM 数据读极少（CPU 很少 load 指令区域），调试读通过 SBA
// 为简化综合，数据读和调试读端口也接到 SDPB B 端口（多路复用）
// 但 SDPB 每个 block 只有单个 B 读端口，指令读和数据读不能同时发生
// 这在 RV32I 中仅当 CPU load 指令区域时才冲突（属于正常程序的异常情况）
//
// 综合实现：
//   - 8 个 SDPB，A 口写，B 口读
//   - B 口地址：指令读优先（iaddr），数据/调试读只在 dren/dbg_ren 时生效
//   - 读数据输出延迟 1 周期（同步输出），由 cpu_core 的 iram_wait 处理

// 读地址 mux：dbg_ren 优先 > dren > 指令读
wire        rd_use_dbg   = dbg_ren;
wire        rd_use_d     = dren & ~dbg_ren;
wire [11:0] rd_waddr12   = rd_use_dbg ? dbg_addr[13:2] :
                           rd_use_d   ? daddr[13:2]    :
                                        i_waddr12;
wire [2:0]  rd_blksel    = rd_waddr12[11:9];
wire [8:0]  rd_row       = rd_waddr12[8:0];
wire [13:0] rd_addrb     = {rd_row, 5'b0};

// 延迟 1 周期的 bank 选择（同步读输出对齐）
reg [2:0] rd_blksel_d1;
reg       rd_use_dbg_d1;
reg       rd_use_d_d1;
always @(posedge clk) begin
    rd_blksel_d1  <= rd_blksel;
    rd_use_dbg_d1 <= rd_use_dbg;
    rd_use_d_d1   <= rd_use_d;
end

// 8 个 SDPB 实例（bank 0~7）
wire [31:0] bdo [0:7];

genvar gi;
generate
for (gi = 0; gi < 8; gi = gi + 1) begin : gen_sdpb
    SDPB #(
        .READ_MODE(1'b0),        // 读后输出（synchronous）
        .BIT_WIDTH_0(32),        // 写端口 32bit
        .BIT_WIDTH_1(32),        // 读端口 32bit
        .BLK_SEL_0(gi[2:0]),     // 写 bank 编号（固定参数）
        .BLK_SEL_1(gi[2:0]),     // 读 bank 编号（固定参数）
        .RESET_MODE("SYNC"),
        .INIT_RAM_00(256'h0),
        .INIT_RAM_01(256'h0),
        .INIT_RAM_02(256'h0),
        .INIT_RAM_03(256'h0),
        .INIT_RAM_04(256'h0),
        .INIT_RAM_05(256'h0),
        .INIT_RAM_06(256'h0),
        .INIT_RAM_07(256'h0),
        .INIT_RAM_08(256'h0),
        .INIT_RAM_09(256'h0),
        .INIT_RAM_0A(256'h0),
        .INIT_RAM_0B(256'h0),
        .INIT_RAM_0C(256'h0),
        .INIT_RAM_0D(256'h0),
        .INIT_RAM_0E(256'h0),
        .INIT_RAM_0F(256'h0),
        .INIT_RAM_10(256'h0),
        .INIT_RAM_11(256'h0),
        .INIT_RAM_12(256'h0),
        .INIT_RAM_13(256'h0),
        .INIT_RAM_14(256'h0),
        .INIT_RAM_15(256'h0),
        .INIT_RAM_16(256'h0),
        .INIT_RAM_17(256'h0),
        .INIT_RAM_18(256'h0),
        .INIT_RAM_19(256'h0),
        .INIT_RAM_1A(256'h0),
        .INIT_RAM_1B(256'h0),
        .INIT_RAM_1C(256'h0),
        .INIT_RAM_1D(256'h0),
        .INIT_RAM_1E(256'h0),
        .INIT_RAM_1F(256'h0),
        .INIT_RAM_20(256'h0),
        .INIT_RAM_21(256'h0),
        .INIT_RAM_22(256'h0),
        .INIT_RAM_23(256'h0),
        .INIT_RAM_24(256'h0),
        .INIT_RAM_25(256'h0),
        .INIT_RAM_26(256'h0),
        .INIT_RAM_27(256'h0),
        .INIT_RAM_28(256'h0),
        .INIT_RAM_29(256'h0),
        .INIT_RAM_2A(256'h0),
        .INIT_RAM_2B(256'h0),
        .INIT_RAM_2C(256'h0),
        .INIT_RAM_2D(256'h0),
        .INIT_RAM_2E(256'h0),
        .INIT_RAM_2F(256'h0),
        .INIT_RAM_30(256'h0),
        .INIT_RAM_31(256'h0),
        .INIT_RAM_32(256'h0),
        .INIT_RAM_33(256'h0),
        .INIT_RAM_34(256'h0),
        .INIT_RAM_35(256'h0),
        .INIT_RAM_36(256'h0),
        .INIT_RAM_37(256'h0),
        .INIT_RAM_38(256'h0),
        .INIT_RAM_39(256'h0),
        .INIT_RAM_3A(256'h0),
        .INIT_RAM_3B(256'h0),
        .INIT_RAM_3C(256'h0),
        .INIT_RAM_3D(256'h0),
        .INIT_RAM_3E(256'h0),
        .INIT_RAM_3F(256'h0)
    ) u_sdpb (
        // 写端口 A
        .CLKA   (clk),
        .RESETA (1'b0),
        .CEA    (wr_wen & (wr_blksel == gi[2:0])),
        .ADA    (wr_addra),
        .DI     (wr_wdata),
        .BLKSELA(wr_blksel),
        // 读端口 B
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

// 同步读输出 mux（使用延迟后的 bank 选择）
always @(posedge clk) begin
    idata    <= bdo[rd_blksel_d1];
    drdata   <= bdo[rd_blksel_d1];
    dbg_rdata<= bdo[rd_blksel_d1];
end

`else

// ============================================================
//  仿真路径：$readmemh 行为模型（组合读，与 Phase 1 行为一致）
//  cpu_core 的 iram_wait 会在综合路径下产生效果；
//  仿真路径组合读，iram_wait=1 的 hold 周期多等 1 拍但不影响数据正确性
// ============================================================
reg [31:0] mem [0:4095];

wire [11:0] iaddr_idx    = iaddr[13:2];
wire [11:0] daddr_idx    = daddr[13:2];
wire [11:0] dbg_addr_idx = dbg_addr[13:2];

// 组合读（与 Phase 1 行为一致）
always @(*) begin
    idata     = mem[iaddr_idx];
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

initial begin
    $readmemh("rtl/perips/iram_init.mem", mem);
end

`endif // SYNTHESIS

endmodule

`endif // IRAM_SV
