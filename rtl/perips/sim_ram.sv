`ifndef SIM_RAM_SV
`define SIM_RAM_SV

// ============================================================
//  仿真用合一 RAM（IRAM + DRAM）
//  地址空间：0x80000000 ~ 0x80007FFF（32 KB）
//    低 16KB（0x80000000 ~ 0x80003FFF）：IRAM（指令）
//    高 16KB（0x80004000 ~ 0x80007FFF）：DRAM（数据）
//  8192 个 32-bit 字，word 索引 = addr[14:2]
//
//  指令端口：组合读
//  数据端口：组合读 + 同步写（支持字节使能）
//  调试端口：组合读 + 同步写（支持字节使能）
//
//  initial 块内含硬编码测试程序，输出 "Hello!\n" 到 UART
//  UART 基址：0x10000000
//    TXDATA  0x10000000（写[7:0]发送一字节）
//    STATUS  0x10000008（[0]=TX忙，轮询等待）
// ============================================================
module SimRAM (
    input  wire        clk,

    // 指令端口（来自 CPU IF，组合读）
    input  wire [31:0] iaddr,
    output wire [31:0] idata,

    // 数据端口（来自 CPU MEM，组合读 + 同步写）
    input  wire [31:0] daddr,
    input  wire        dren,
    input  wire        dwen,
    input  wire [3:0]  dbe,
    input  wire [31:0] dwdata,
    output wire [31:0] drdata,

    // 调试端口（来自 Debug Module System Bus Access，组合读 + 同步写）
    input  wire [31:0] dbg_addr,
    input  wire        dbg_ren,
    input  wire        dbg_wen,
    input  wire [3:0]  dbg_be,
    input  wire [31:0] dbg_wdata,
    output wire [31:0] dbg_rdata
);

// 8192 个 32-bit 字 = 32 KB
reg [31:0] mem [0:8191];

// word 地址索引（取 addr[14:2]，共 13 位 → 8192 项）
wire [12:0] iaddr_idx   = iaddr[14:2];
wire [12:0] daddr_idx   = daddr[14:2];
wire [12:0] dbg_addr_idx = dbg_addr[14:2];

// ---------------------------------------------------------
//  组合读端口
// ---------------------------------------------------------
assign idata    = mem[iaddr_idx];
assign drdata   = mem[daddr_idx];
assign dbg_rdata = mem[dbg_addr_idx];

// ---------------------------------------------------------
//  数据端口同步写（时钟域：clk，字节使能）
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
//  调试端口同步写（时钟域：clk，字节使能）
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
//  硬编码测试程序（word 索引 0 起，物理地址 0x80000000）
//
//  程序目标：输出 "Hello!\n" 到 UART（地址 0x10000000），然后死循环
//
//  UART 寄存器：
//    x1 = 0x10000000（TXDATA）
//    x3 = 0x10000008（STATUS）
//
//  内联 wait_tx = 3 条指令（每发一个字符前展开）：
//    lw  x4, 0(x3)    ; 读 STATUS
//    andi x4, x4, 1   ; 取 TX忙 位
//    bne x4, x0, -8   ; 若忙则跳回 lw
//
//  机器码计算说明（RV32I 编码）：
//
//  [0]  lui  x1, 0x10000   → imm20=0x10000, rd=1, op=0110111
//         = {20'h10000, 5'd1, 7'b0110111} = 32'h100000B7
//
//  [1]  addi x3, x1, 8     → imm12=8, rs1=1, f3=000, rd=3, op=0010011
//         = {12'd8, 5'd1, 3'b000, 5'd3, 7'b0010011} = 32'h00808193
//
//  [2]  addi x2, x0, 0x48  → imm12=0x48='H', rs1=0, rd=2
//         = {12'h048, 5'd0, 3'b000, 5'd2, 7'b0010011} = 32'h04800113
//
//  wait_tx（展开）：
//  lw  x4, 0(x3): imm=0, rs1=3, f3=010, rd=4, op=0000011
//         = {12'd0, 5'd3, 3'b010, 5'd4, 7'b0000011} = 32'h0001A203
//  andi x4, x4, 1: imm=1, rs1=4, f3=111, rd=4, op=0010011
//         = {12'd1, 5'd4, 3'b111, 5'd4, 7'b0010011} = 32'h00127213
//  bne  x4, x0, -8: offset=-8（跳回 lw）
//         B型偏移编码：-8 = 0b1_1111_1111_1000（13位补码）
//         imm[12]=1, imm[11]=1, imm[10:5]=6'b111111, imm[4:1]=4'b1100
//         = {1'b1,6'b111111,5'd0,5'd4,3'b001,4'b1100,1'b1,7'b1100011}
//         = 32'hFE021CE3
//
//  sb  x2, 0(x1): S型 imm=0, rs2=2, rs1=1, f3=000, op=0100011
//         = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'b00000, 7'b0100011}
//         = 32'h00208023
//
//  jal x0, 0: offset=0，死循环（跳到自身）
//         J型全零偏移 = 32'h0000006F
// ---------------------------------------------------------
initial begin : init_prog
    integer i;

    // [0]  lui  x1, 0x10000      → x1 = 0x10000000 (UART TXDATA)
    mem[0]  = 32'h100000B7;
    // [1]  addi x3, x1, 8        → x3 = 0x10000008 (UART STATUS)
    mem[1]  = 32'h00808193;

    // ---- 发送 'H' (0x48) ----
    // [2]  addi x2, x0, 0x48
    mem[2]  = 32'h04800113;
    // [3]  lw   x4, 0(x3)        （wait_tx: 轮询 STATUS[0]）
    mem[3]  = 32'h0001A203;
    // [4]  andi x4, x4, 1
    mem[4]  = 32'h00127213;
    // [5]  bne  x4, x0, -8       （TX忙则跳回[3]）
    mem[5]  = 32'hFE021CE3;
    // [6]  sb   x2, 0(x1)        （发送字节）
    mem[6]  = 32'h00208023;

    // ---- 发送 'e' (0x65) ----
    // [7]  addi x2, x0, 0x65
    mem[7]  = 32'h06500113;
    // [8]  lw   x4, 0(x3)
    mem[8]  = 32'h0001A203;
    // [9]  andi x4, x4, 1
    mem[9]  = 32'h00127213;
    // [10] bne  x4, x0, -8
    mem[10] = 32'hFE021CE3;
    // [11] sb   x2, 0(x1)
    mem[11] = 32'h00208023;

    // ---- 发送 'l' (0x6C) ----
    // [12] addi x2, x0, 0x6C
    mem[12] = 32'h06C00113;
    // [13] lw   x4, 0(x3)
    mem[13] = 32'h0001A203;
    // [14] andi x4, x4, 1
    mem[14] = 32'h00127213;
    // [15] bne  x4, x0, -8
    mem[15] = 32'hFE021CE3;
    // [16] sb   x2, 0(x1)
    mem[16] = 32'h00208023;

    // ---- 发送 'l' (0x6C) ----
    // [17] addi x2, x0, 0x6C
    mem[17] = 32'h06C00113;
    // [18] lw   x4, 0(x3)
    mem[18] = 32'h0001A203;
    // [19] andi x4, x4, 1
    mem[19] = 32'h00127213;
    // [20] bne  x4, x0, -8
    mem[20] = 32'hFE021CE3;
    // [21] sb   x2, 0(x1)
    mem[21] = 32'h00208023;

    // ---- 发送 'o' (0x6F) ----
    // [22] addi x2, x0, 0x6F
    mem[22] = 32'h06F00113;
    // [23] lw   x4, 0(x3)
    mem[23] = 32'h0001A203;
    // [24] andi x4, x4, 1
    mem[24] = 32'h00127213;
    // [25] bne  x4, x0, -8
    mem[25] = 32'hFE021CE3;
    // [26] sb   x2, 0(x1)
    mem[26] = 32'h00208023;

    // ---- 发送 '!' (0x21) ----
    // [27] addi x2, x0, 0x21
    mem[27] = 32'h02100113;
    // [28] lw   x4, 0(x3)
    mem[28] = 32'h0001A203;
    // [29] andi x4, x4, 1
    mem[29] = 32'h00127213;
    // [30] bne  x4, x0, -8
    mem[30] = 32'hFE021CE3;
    // [31] sb   x2, 0(x1)
    mem[31] = 32'h00208023;

    // ---- 发送 '\n' (0x0A) ----
    // [32] addi x2, x0, 0x0A
    mem[32] = 32'h00A00113;
    // [33] lw   x4, 0(x3)
    mem[33] = 32'h0001A203;
    // [34] andi x4, x4, 1
    mem[34] = 32'h00127213;
    // [35] bne  x4, x0, -8
    mem[35] = 32'hFE021CE3;
    // [36] sb   x2, 0(x1)
    mem[36] = 32'h00208023;

    // ---- 死循环 ----
    // [37] jal  x0, 0             （原地跳转，offset=0）
    mem[37] = 32'h0000006F;

    // 剩余地址初始化为 NOP（addi x0, x0, 0 = 0x00000013）
    for (i = 38; i < 8192; i = i + 1) begin
        mem[i] = 32'h0000_0013;
    end
end

endmodule

`endif // SIM_RAM_SV
