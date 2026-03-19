`ifndef DRAM_SV
`define DRAM_SV

// ============================================================
//  DRAM（Data RAM）8KB
//  地址空间：0x80004000 ~ 0x80005FFF
//  2048 个 32-bit 字，word 索引 = addr[12:2]
//
//  端口：
//    数据端口（CPU MEM）：组合读 + 同步写（字节使能）
//    调试端口（DM SBA）：组合读 + 同步写（字节使能）
//
//  Yosys synth_gowin -bsram 自动推断为 4 块 BSRAM（每块 2KB）
// ============================================================
module DRAM (
    input  wire        clk,

    // 数据端口（来自 CPU MEM，组合读 + 同步写）
    input  wire [31:0] daddr,
    input  wire        dren,
    input  wire        dwen,
    input  wire [3:0]  dbe,
    input  wire [31:0] dwdata,
    output wire [31:0] drdata,

    // 调试端口（来自 DebugModule SBA，组合读 + 同步写）
    input  wire [31:0] dbg_addr,
    input  wire        dbg_ren,
    input  wire        dbg_wen,
    input  wire [3:0]  dbg_be,
    input  wire [31:0] dbg_wdata,
    output wire [31:0] dbg_rdata
);

// 2048 个 32-bit 字 = 8KB
reg [31:0] mem [0:2047];

// word 地址索引（取 addr[12:2]，共 11 位 → 2048 项）
wire [10:0] daddr_idx    = daddr[12:2];
wire [10:0] dbg_addr_idx = dbg_addr[12:2];

// ---------------------------------------------------------
//  组合读端口
// ---------------------------------------------------------
assign drdata    = mem[daddr_idx];
assign dbg_rdata = mem[dbg_addr_idx];

// ---------------------------------------------------------
//  数据端口同步写（字节使能）
// ---------------------------------------------------------
always @(posedge clk) begin
    if (dwen) begin
        if (dbe[0]) mem[daddr_idx][ 7: 0] <= dwdata[ 7: 0];
        if (dbe[1]) mem[daddr_idx][15: 8] <= dwdata[15: 8];
        if (dbe[2]) mem[daddr_idx][23:16] <= dwdata[23:16];
        if (dbe[3]) mem[daddr_idx][31:24] <= dwdata[31:24];
    end
end

// ---------------------------------------------------------
//  调试端口同步写（字节使能）
// ---------------------------------------------------------
always @(posedge clk) begin
    if (dbg_wen) begin
        if (dbg_be[0]) mem[dbg_addr_idx][ 7: 0] <= dbg_wdata[ 7: 0];
        if (dbg_be[1]) mem[dbg_addr_idx][15: 8] <= dbg_wdata[15: 8];
        if (dbg_be[2]) mem[dbg_addr_idx][23:16] <= dbg_wdata[23:16];
        if (dbg_be[3]) mem[dbg_addr_idx][31:24] <= dbg_wdata[31:24];
    end
end

// ---------------------------------------------------------
//  初始化：全零（仿真用，综合时 Yosys 忽略 initial 块）
// ---------------------------------------------------------
integer i;
initial begin
    for (i = 0; i < 2048; i = i + 1)
        mem[i] = 32'h0000_0000;
end

endmodule

`endif // DRAM_SV
