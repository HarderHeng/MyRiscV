// =============================================================
// 文件：rtl/core/id_ex.sv
// 描述：ID/EX 流水线寄存器
//       - 传递 ID 阶段所有控制和数据信号到 EX 阶段
//       - flush 时将所有控制信号清零（插入 NOP 气泡）
//       - 同步高有效复位
// =============================================================
`ifndef ID_EX_SV
`define ID_EX_SV

`include "core_define.svh"

module IDEX (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,    // 控制冒险（分支/跳转）或 Load-use 时冲刷

    // ---- ID 阶段输入 ----
    input  wire [31:0] id_pc,
    input  wire [31:0] id_pc_plus4,
    input  wire [3:0]  id_alu_op,
    input  wire [31:0] id_alu_src1,
    input  wire [31:0] id_alu_src2,
    input  wire        id_mem_ren,
    input  wire        id_mem_wen,
    input  wire [2:0]  id_mem_funct3,
    input  wire [31:0] id_mem_wdata,
    input  wire        id_reg_wen,
    input  wire [4:0]  id_reg_waddr,
    input  wire        id_is_branch,
    input  wire [2:0]  id_branch_funct3,
    input  wire        id_is_jmp,
    input  wire [31:0] id_jmp_addr,
    input  wire        id_is_load,

    // ---- EX 阶段输出 ----
    output reg  [31:0] ex_pc,
    output reg  [31:0] ex_pc_plus4,
    output reg  [3:0]  ex_alu_op,
    output reg  [31:0] ex_alu_src1,
    output reg  [31:0] ex_alu_src2,
    output reg         ex_mem_ren,
    output reg         ex_mem_wen,
    output reg  [2:0]  ex_mem_funct3,
    output reg  [31:0] ex_mem_wdata,
    output reg         ex_reg_wen,
    output reg  [4:0]  ex_reg_waddr,
    output reg         ex_is_branch,
    output reg  [2:0]  ex_branch_funct3,
    output reg         ex_is_jmp,
    output reg  [31:0] ex_jmp_addr,
    output reg         ex_is_load
);

    // -------------------------------------------------------
    // 流水线寄存器更新逻辑（同步，posedge clk）
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (rst || flush) begin
            // 复位或冲刷：所有控制信号清零，插入 NOP 气泡
            ex_pc           <= 32'd0;
            ex_pc_plus4     <= 32'd0;
            ex_alu_op       <= 4'd0;
            ex_alu_src1     <= 32'd0;
            ex_alu_src2     <= 32'd0;
            ex_mem_ren      <= 1'b0;
            ex_mem_wen      <= 1'b0;
            ex_mem_funct3   <= 3'b000;
            ex_mem_wdata    <= 32'd0;
            ex_reg_wen      <= 1'b0;
            ex_reg_waddr    <= 5'd0;
            ex_is_branch    <= 1'b0;
            ex_branch_funct3 <= 3'b000;
            ex_is_jmp       <= 1'b0;
            ex_jmp_addr     <= 32'd0;
            ex_is_load      <= 1'b0;
        end else begin
            // 正常传递：锁存 ID 阶段输出
            ex_pc           <= id_pc;
            ex_pc_plus4     <= id_pc_plus4;
            ex_alu_op       <= id_alu_op;
            ex_alu_src1     <= id_alu_src1;
            ex_alu_src2     <= id_alu_src2;
            ex_mem_ren      <= id_mem_ren;
            ex_mem_wen      <= id_mem_wen;
            ex_mem_funct3   <= id_mem_funct3;
            ex_mem_wdata    <= id_mem_wdata;
            ex_reg_wen      <= id_reg_wen;
            ex_reg_waddr    <= id_reg_waddr;
            ex_is_branch    <= id_is_branch;
            ex_branch_funct3 <= id_branch_funct3;
            ex_is_jmp       <= id_is_jmp;
            ex_jmp_addr     <= id_jmp_addr;
            ex_is_load      <= id_is_load;
        end
    end

endmodule

`endif // ID_EX_SV
