// =============================================================
// 文件：rtl/core/ex_mem.sv
// 描述：EX/MEM 流水线寄存器
//       - 传递 EX 阶段所有控制和数据信号到 MEM 阶段
//       - flush 时将所有控制信号清零（插入 NOP 气泡）
//       - 同步高有效复位
// =============================================================
`ifndef EX_MEM_SV
`define EX_MEM_SV

`include "core_define.svh"

module EXMEM (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,

    // ---- EX 阶段输入 ----
    input  wire [31:0] ex_alu_result,
    input  wire        ex_mem_ren,
    input  wire        ex_mem_wen,
    input  wire [2:0]  ex_mem_funct3,
    input  wire [31:0] ex_mem_wdata,
    input  wire [31:0] ex_mem_addr,
    input  wire        ex_reg_wen,
    input  wire [4:0]  ex_reg_waddr,
    input  wire [31:0] ex_reg_wdata,
    input  wire        ex_is_load,

    // ---- MEM 阶段输出 ----
    output reg  [31:0] mem_alu_result,
    output reg         mem_mem_ren,
    output reg         mem_mem_wen,
    output reg  [2:0]  mem_mem_funct3,
    output reg  [31:0] mem_mem_wdata,
    output reg  [31:0] mem_mem_addr,
    output reg         mem_reg_wen,
    output reg  [4:0]  mem_reg_waddr,
    output reg  [31:0] mem_reg_wdata,
    output reg         mem_is_load
);

    // -------------------------------------------------------
    // 流水线寄存器更新逻辑（同步，posedge clk）
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (rst || flush) begin
            // 复位或冲刷：清零所有信号，插入 NOP 气泡
            mem_alu_result  <= 32'd0;
            mem_mem_ren     <= 1'b0;
            mem_mem_wen     <= 1'b0;
            mem_mem_funct3  <= 3'b000;
            mem_mem_wdata   <= 32'd0;
            mem_mem_addr    <= 32'd0;
            mem_reg_wen     <= 1'b0;
            mem_reg_waddr   <= 5'd0;
            mem_reg_wdata   <= 32'd0;
            mem_is_load     <= 1'b0;
        end else begin
            // 正常传递：锁存 EX 阶段输出
            mem_alu_result  <= ex_alu_result;
            mem_mem_ren     <= ex_mem_ren;
            mem_mem_wen     <= ex_mem_wen;
            mem_mem_funct3  <= ex_mem_funct3;
            mem_mem_wdata   <= ex_mem_wdata;
            mem_mem_addr    <= ex_mem_addr;
            mem_reg_wen     <= ex_reg_wen;
            mem_reg_waddr   <= ex_reg_waddr;
            mem_reg_wdata   <= ex_reg_wdata;
            mem_is_load     <= ex_is_load;
        end
    end

endmodule

`endif // EX_MEM_SV
