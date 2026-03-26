// =============================================================
// 文件：rtl/core/regfile.sv
// 描述：32×32 通用寄存器堆
//       - 两个读端口（仿真：组合异步；综合：SDPB 同步读 + regfile_wait 气泡）
//       - 一个同步写端口（WB 阶段，posedge clk）
//       - 一个调试读端口（仿真：组合异步；综合：SDPB 同步读）
//       - 一个调试同步写端口
//       - x0 硬编码为 0，写入忽略
//
// 综合路径（`ifdef SYNTHESIS）：
//   使用 3 × SDPB 原语（每读端口独立一个 SDPB，写口同时驱动三份）
//   SDPB 为同步读（B 口注册输出），需等 1 拍数据有效
//   regfile_wait 输出 1 表示读请求发出、数据尚未稳定，流水线应暂停 1 周期
//
// 仿真路径（`ifndef SYNTHESIS）：
//   保持组合异步读，regfile_wait 恒为 0
// =============================================================
`ifndef REGFILE_SV
`define REGFILE_SV

`include "core_define.svh"

module RegFile (
    input  wire        clk,
    input  wire        rst,

    // 读端口1
    input  wire [4:0]  raddr1,
    output wire [31:0] rdata1,

    // 读端口2
    input  wire [4:0]  raddr2,
    output wire [31:0] rdata2,

    // 写端口（同步，WB 阶段）
    input  wire        wen,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata,

    // 调试读端口
    input  wire [4:0]  dbg_raddr,
    output wire [31:0] dbg_rdata,

    // 调试写端口（同步）
    input  wire        dbg_wen,
    input  wire [4:0]  dbg_waddr,
    input  wire [31:0] dbg_wdata,

    // 综合路径：读等待信号（高有效，持续 1 个周期）
    // 仿真路径：恒为 0
    output wire        regfile_wait
);

`ifdef SYNTHESIS

// ============================================================
//  综合路径：3 × SDPB 原语（每读端口一个实例）
//  配置：BIT_WIDTH=32，深度 512（仅使用低 32 项）
//  写口：A 口（CLKA/CEA/ADA/DI/BLKSELA）
//  读口：B 口（CLKB/CEB/OCE/ADB/BLKSELB/DO），同步注册输出
//
//  由于 SDPB 只有一个 A 写口，三个实例同时写相同数据（镜像写）
//  三个 B 读口分别给 rdata1、rdata2、dbg_rdata
//
//  regfile_wait：每次读地址稳定后等 1 拍，数据在下个周期有效
//  实现：在发起读请求的时钟沿输出 wait=1，次拍 wait=0，数据有效
// ============================================================

// 写使能：WB 写回或调试写（x0 忽略）
wire        act_wen   = (wen     && (waddr    != 5'd0))
                      | (dbg_wen && (dbg_waddr != 5'd0));
wire [4:0]  act_waddr = dbg_wen ? dbg_waddr : waddr;
wire [31:0] act_wdata = dbg_wen ? dbg_wdata : wdata;

// SDPB 地址：BIT_WIDTH_0/1=32 时，ADA/ADB 为 9 位（bit[13:2] = {4'b0, addr[4:0]}）
wire [13:0] sdpb_waddr = {9'b0, act_waddr};
wire [13:0] sdpb_raddr1 = {9'b0, raddr1};
wire [13:0] sdpb_raddr2 = {9'b0, raddr2};
wire [13:0] sdpb_raddr_dbg = {9'b0, dbg_raddr};

wire [31:0] sdpb_do1, sdpb_do2, sdpb_do_dbg;

// SDPB 实例 1：rdata1
SDPB #(
    .READ_MODE(1'b0),
    .BIT_WIDTH_0(32),
    .BIT_WIDTH_1(32),
    .BLK_SEL_0(3'b000),
    .BLK_SEL_1(3'b000),
    .RESET_MODE("SYNC")
) u_sdpb_r1 (
    .CLKA   (clk),
    .RESETA (1'b0),
    .CEA    (act_wen),
    .ADA    (sdpb_waddr),
    .DI     (act_wdata),
    .BLKSELA(3'b000),
    .CLKB   (clk),
    .RESETB (1'b0),
    .CEB    (1'b1),
    .OCE    (1'b1),
    .ADB    (sdpb_raddr1),
    .DO     (sdpb_do1),
    .BLKSELB(3'b000)
);

// SDPB 实例 2：rdata2
SDPB #(
    .READ_MODE(1'b0),
    .BIT_WIDTH_0(32),
    .BIT_WIDTH_1(32),
    .BLK_SEL_0(3'b000),
    .BLK_SEL_1(3'b000),
    .RESET_MODE("SYNC")
) u_sdpb_r2 (
    .CLKA   (clk),
    .RESETA (1'b0),
    .CEA    (act_wen),
    .ADA    (sdpb_waddr),
    .DI     (act_wdata),
    .BLKSELA(3'b000),
    .CLKB   (clk),
    .RESETB (1'b0),
    .CEB    (1'b1),
    .OCE    (1'b1),
    .ADB    (sdpb_raddr2),
    .DO     (sdpb_do2),
    .BLKSELB(3'b000)
);

// SDPB 实例 3：dbg_rdata
SDPB #(
    .READ_MODE(1'b0),
    .BIT_WIDTH_0(32),
    .BIT_WIDTH_1(32),
    .BLK_SEL_0(3'b000),
    .BLK_SEL_1(3'b000),
    .RESET_MODE("SYNC")
) u_sdpb_dbg (
    .CLKA   (clk),
    .RESETA (1'b0),
    .CEA    (act_wen),
    .ADA    (sdpb_waddr),
    .DI     (act_wdata),
    .BLKSELA(3'b000),
    .CLKB   (clk),
    .RESETB (1'b0),
    .CEB    (1'b1),
    .OCE    (1'b1),
    .ADB    (sdpb_raddr_dbg),
    .DO     (sdpb_do_dbg),
    .BLKSELB(3'b000)
);

// regfile_wait：每次新指令进入 ID（raddr 变化沿）等 1 拍
// 实现：复位后或 IRAM 取到新指令后等 1 拍（与 iram_wait 配合，
// 此处简化为恒高 1 拍延迟，由外部 regfile_wait 寄存器控制）
// cpu_core 负责在 if_hold 中串入 regfile_wait，保证 IFID hold 住时
// raddr 不变，因此 SDPB 下拍输出即正确数据。
// 综合路径恒输出 wait=1（始终要求 1 拍延迟），cpu_core 消化该 stall
// 注意：iram_wait=1 时 IF/ID 被 hold，此时 raddr 不变，rdata SDPB
// 输出已在复位等待的那 1 拍之后稳定；运行时每次 IFID 推进后
// regfile_wait 需要 1 拍。
//
// 简洁实现：regfile_wait_reg 跟随 if_hold 取反（IFID 推进时置 1，
// 但这形成循环依赖）。
// 正确实现：regfile_wait 是从 IFID 推进沿起的 1 拍等待。
// 与 iram_wait 完全对称：在 IFID 推进（即 !if_hold）的下一拍
// regfile_wait=1，再下一拍 rdata 有效，regfile_wait=0。
// cpu_core 内部生成此信号（类似 iram_wait），此处直接输出占位 0，
// 实际 wait 逻辑移到 cpu_core 统一管理（见 cpu_core.sv）。
assign regfile_wait = 1'b0;  // cpu_core 内部产生，此处不重复

// x0 硬编码为 0
assign rdata1    = (raddr1    == 5'd0) ? 32'd0 : sdpb_do1;
assign rdata2    = (raddr2    == 5'd0) ? 32'd0 : sdpb_do2;
assign dbg_rdata = (dbg_raddr == 5'd0) ? 32'd0 : sdpb_do_dbg;

`else

// ============================================================
//  仿真路径：行为模型，组合异步读，与 Phase 1 一致
// ============================================================
reg [31:0] regs [0:31];

integer i;
always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] <= 32'd0;
    end else begin
        if (wen && (waddr != 5'd0))
            regs[waddr] <= wdata;
        if (dbg_wen && (dbg_waddr != 5'd0))
            regs[dbg_waddr] <= dbg_wdata;
    end
end

assign rdata1    = (raddr1    == 5'd0) ? 32'd0 : regs[raddr1];
assign rdata2    = (raddr2    == 5'd0) ? 32'd0 : regs[raddr2];
assign dbg_rdata = (dbg_raddr == 5'd0) ? 32'd0 : regs[dbg_raddr];
assign regfile_wait = 1'b0;

`endif

endmodule

`endif // REGFILE_SV
