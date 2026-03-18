// =============================================================
// 文件：rtl/core/mem_wb.sv
// 描述：MEM/WB 流水线寄存器
//       - 传递 MEM 阶段写回信号到 WB 阶段
//       - flush/rst 时清零所有控制信号
//       - 同步高有效复位
// =============================================================
`ifndef MEM_WB_SV
`define MEM_WB_SV

`include "core_define.svh"

module MEMWB (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,

    // ---- MEM 阶段输入 ----
    input  wire        mem_reg_wen,
    input  wire [4:0]  mem_reg_waddr,
    input  wire [31:0] mem_reg_wdata,

    // ---- WB 阶段输出 ----
    output reg         wb_reg_wen,
    output reg  [4:0]  wb_reg_waddr,
    output reg  [31:0] wb_reg_wdata
);

    // -------------------------------------------------------
    // 流水线寄存器更新逻辑（同步，posedge clk）
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (rst || flush) begin
            // 复位或冲刷：禁用写回
            wb_reg_wen   <= 1'b0;
            wb_reg_waddr <= 5'd0;
            wb_reg_wdata <= 32'd0;
        end else begin
            // 正常传递：锁存 MEM 阶段写回信号
            wb_reg_wen   <= mem_reg_wen;
            wb_reg_waddr <= mem_reg_waddr;
            wb_reg_wdata <= mem_reg_wdata;
        end
    end

endmodule

`endif // MEM_WB_SV
