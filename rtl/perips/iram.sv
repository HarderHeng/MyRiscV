`ifndef IRAM_SV
`define IRAM_SV

// ============================================================
//  IRAM（Instruction RAM）16KB
//  地址空间：0x80000000 ~ 0x80003FFF
//  4096 个 32-bit 字，word 索引 = addr[13:2]
//
//  端口：
//    指令端口（CPU IF）：组合读（始终连接，不需要选通）
//    数据端口（CPU MEM）：组合读 + 同步写（字节使能）
//    调试端口（DM SBA）：组合读 + 同步写（字节使能）
//
//  初始化：$readmemh("iram_init.mem", mem)
//    Yosys synth_gowin -bsram 自动推断为 8 块 BSRAM（每块 2KB）
// ============================================================
module IRAM (
    input  wire        clk,

    // 指令端口（来自 CPU IF，组合读，始终连接）
    input  wire [31:0] iaddr,
    output wire [31:0] idata,

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

// 4096 个 32-bit 字 = 16KB
reg [31:0] mem [0:4095];

// word 地址索引（取 addr[13:2]，共 12 位 → 4096 项）
wire [11:0] iaddr_idx    = iaddr[13:2];
wire [11:0] daddr_idx    = daddr[13:2];
wire [11:0] dbg_addr_idx = dbg_addr[13:2];

// ---------------------------------------------------------
//  组合读端口
// ---------------------------------------------------------
assign idata     = mem[iaddr_idx];
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
//  初始化（$readmemh 加载 .mem 文件）
//  综合时 Yosys 读取 iram_init.mem 作为 BSRAM 初始内容
//  路径相对于 make 运行目录（项目根目录）
// ---------------------------------------------------------
initial begin
    $readmemh("rtl/perips/iram_init.mem", mem);
end

endmodule

`endif // IRAM_SV
