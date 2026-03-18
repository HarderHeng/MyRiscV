// =============================================================
// 文件：rtl/core/regfile.sv
// 描述：32×32 通用寄存器堆
//       - 两个异步读端口（组合逻辑）
//       - 一个同步写端口（WB 阶段，posedge clk）
//       - 一个调试异步读端口 + 一个调试同步写端口
//       - x0 硬编码为 0，写入忽略
//       - 读写同地址时，读返回寄存器当前值（forwarding 由外部保证）
//       - 复位时所有寄存器清零
// =============================================================
`ifndef REGFILE_SV
`define REGFILE_SV

`include "core_define.svh"

module RegFile (
    input  wire        clk,
    input  wire        rst,

    // 读端口1（组合异步）
    input  wire [4:0]  raddr1,
    output wire [31:0] rdata1,

    // 读端口2（组合异步）
    input  wire [4:0]  raddr2,
    output wire [31:0] rdata2,

    // 写端口（同步，WB 阶段）
    input  wire        wen,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata,

    // 调试读端口（组合异步，供 Debug Module 使用）
    input  wire [4:0]  dbg_raddr,
    output wire [31:0] dbg_rdata,

    // 调试写端口（同步，供 Debug Module 使用）
    input  wire        dbg_wen,
    input  wire [4:0]  dbg_waddr,
    input  wire [31:0] dbg_wdata
);

    // 32 个 32 位寄存器（reg[0] 始终为 0）
    reg [31:0] regs [0:31];

    // -------------------------------------------------------
    // 同步写逻辑（posedge clk，同步高有效复位）
    // -------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            // 复位时所有寄存器清零
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else begin
            // WB 阶段写回（x0 写入忽略）
            if (wen && (waddr != 5'd0))
                regs[waddr] <= wdata;
            // 调试写端口（x0 写入忽略）
            if (dbg_wen && (dbg_waddr != 5'd0))
                regs[dbg_waddr] <= dbg_wdata;
        end
    end

    // -------------------------------------------------------
    // 组合读逻辑（异步）：x0 硬编码为 0
    // -------------------------------------------------------
    assign rdata1    = (raddr1    == 5'd0) ? 32'd0 : regs[raddr1];
    assign rdata2    = (raddr2    == 5'd0) ? 32'd0 : regs[raddr2];
    assign dbg_rdata = (dbg_raddr == 5'd0) ? 32'd0 : regs[dbg_raddr];

endmodule

`endif // REGFILE_SV
