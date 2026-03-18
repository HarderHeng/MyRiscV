// =============================================================
// 文件：rtl/core/ex.sv
// 描述：EX 阶段 —— ALU 计算、分支判断、跳转地址确定
//       - 实例化 ALU 模块进行运算
//       - 根据 branch_funct3 判断条件分支是否成立
//       - JAL/JALR：无条件跳转，reg_wdata = pc+4
//       - 其他指令：reg_wdata = alu_result
//       - 纯组合逻辑（always @(*)）
// =============================================================
`ifndef EX_SV
`define EX_SV

`include "core_define.svh"
`include "../alu/alu.svh"

module Execute (
    input  wire        rst,

    // 来自 ID/EX 流水线寄存器
    input  wire [31:0] pc,
    input  wire [31:0] pc_plus4,
    input  wire [3:0]  alu_op,
    input  wire [31:0] alu_src1,
    input  wire [31:0] alu_src2,
    input  wire        mem_ren,
    input  wire        mem_wen,
    input  wire [2:0]  mem_funct3,
    input  wire [31:0] mem_wdata,
    input  wire        reg_wen,
    input  wire [4:0]  reg_waddr,
    input  wire        is_branch,
    input  wire [2:0]  branch_funct3,
    input  wire        is_jmp,
    input  wire [31:0] jmp_addr,
    input  wire        is_load,

    // 输出到 EX/MEM 流水线寄存器
    output reg  [31:0] alu_result,
    output reg         mem_ren_o,
    output reg         mem_wen_o,
    output reg  [2:0]  mem_funct3_o,
    output reg  [31:0] mem_wdata_o,
    output reg  [31:0] mem_addr_o,      // = alu_result（Load/Store 地址）
    output reg         reg_wen_o,
    output reg  [4:0]  reg_waddr_o,
    output reg  [31:0] reg_wdata_o,     // ALU 结果 或 pc+4（JAL/JALR）
    output reg         is_load_o,

    // 跳转输出（到 IF 阶段）
    output reg         jmp,             // 实际跳转信号（分支成立或无条件跳转）
    output reg  [31:0] jmp_addr_o       // 跳转目标地址
);

    // -------------------------------------------------------
    // ALU 实例化（组合逻辑）
    // -------------------------------------------------------
    wire [31:0] alu_out;  // ALU 计算结果

    ALU u_alu (
        .alu_op (alu_op),
        .src1   (alu_src1),
        .src2   (alu_src2),
        .result (alu_out)
    );

    // -------------------------------------------------------
    // 分支判断和输出逻辑（组合逻辑 always @(*)）
    // -------------------------------------------------------
    reg branch_taken;  // 条件分支是否成立

    always @(*) begin
        // ---- 默认值 ----
        branch_taken = 1'b0;
        alu_result   = alu_out;
        mem_ren_o    = 1'b0;
        mem_wen_o    = 1'b0;
        mem_funct3_o = 3'b000;
        mem_wdata_o  = 32'd0;
        mem_addr_o   = 32'd0;
        reg_wen_o    = 1'b0;
        reg_waddr_o  = 5'd0;
        reg_wdata_o  = 32'd0;
        is_load_o    = 1'b0;
        jmp          = 1'b0;
        jmp_addr_o   = 32'd0;

        if (!rst) begin
            // ---- ALU 结果 ----
            alu_result = alu_out;

            // ---- 条件分支判断 ----
            if (is_branch) begin
                case (branch_funct3)
                    `F3_BEQ:  branch_taken = (alu_src1 == alu_src2);
                    `F3_BNE:  branch_taken = (alu_src1 != alu_src2);
                    `F3_BLT:  branch_taken = ($signed(alu_src1) < $signed(alu_src2));
                    `F3_BGE:  branch_taken = ($signed(alu_src1) >= $signed(alu_src2));
                    `F3_BLTU: branch_taken = (alu_src1 < alu_src2);
                    `F3_BGEU: branch_taken = (alu_src1 >= alu_src2);
                    default:  branch_taken = 1'b0;
                endcase
                jmp        = branch_taken;
                jmp_addr_o = jmp_addr;  // 分支目标（ID 阶段已计算好）
            end

            // ---- 无条件跳转（JAL/JALR） ----
            if (is_jmp) begin
                jmp        = 1'b1;
                jmp_addr_o = jmp_addr;  // JAL/JALR 目标（ID 阶段已计算好）
            end

            // ---- 写回数据选择 ----
            // JAL/JALR：写回 pc+4；其他指令：写回 ALU 结果
            if (is_jmp)
                reg_wdata_o = pc_plus4;
            else
                reg_wdata_o = alu_out;

            // ---- 直通信号 ----
            mem_ren_o    = mem_ren;
            mem_wen_o    = mem_wen;
            mem_funct3_o = mem_funct3;
            mem_wdata_o  = mem_wdata;
            mem_addr_o   = alu_out;     // Load/Store 地址 = ALU 计算结果
            reg_wen_o    = reg_wen;
            reg_waddr_o  = reg_waddr;
            is_load_o    = is_load;
        end
    end

endmodule

`endif // EX_SV
