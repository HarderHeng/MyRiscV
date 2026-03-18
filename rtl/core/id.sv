// =============================================================
// 文件：rtl/core/id.sv
// 描述：ID 阶段 —— 完整 RV32I 指令译码
//       - 解码 opcode/funct3/funct7，生成控制信号
//       - 前递（Forwarding）选择：EX > MEM > RegFile
//       - 计算立即数（I/S/B/U/J 型）
//       - 生成跳转目标地址（JAL/JALR/B 型）
// =============================================================
`ifndef ID_SV
`define ID_SV

`include "core_define.svh"
`include "../alu/alu.svh"

module InstructionDecode (
    input  wire        rst,

    // 来自 IF/ID 寄存器
    input  wire [31:0] pc,
    input  wire [31:0] inst,

    // 寄存器堆读数据（RegFile 异步读，在前递后选择）
    input  wire [31:0] reg_rdata1,
    input  wire [31:0] reg_rdata2,

    // 前递数据：EX 阶段结果（最高优先级）
    input  wire        fwd_ex_wen,
    input  wire [4:0]  fwd_ex_waddr,
    input  wire [31:0] fwd_ex_wdata,

    // 前递数据：MEM 阶段结果（次优先级）
    input  wire        fwd_mem_wen,
    input  wire [4:0]  fwd_mem_waddr,
    input  wire [31:0] fwd_mem_wdata,

    // 寄存器堆读地址（输出到 RegFile）
    output reg  [4:0]  reg_raddr1,
    output reg  [4:0]  reg_raddr2,

    // ALU 操作数和操作码
    output reg  [3:0]  alu_op,
    output reg  [31:0] alu_src1,
    output reg  [31:0] alu_src2,

    // 访存控制
    output reg         mem_ren,       // Load 使能
    output reg         mem_wen,       // Store 使能
    output reg  [2:0]  mem_funct3,    // 访存粒度（LB/LH/LW/LBU/LHU/SB/SH/SW）
    output reg  [31:0] mem_wdata,     // Store 写数据（rs2，已前递选择）

    // 写回控制
    output reg         reg_wen,
    output reg  [4:0]  reg_waddr,

    // 跳转控制（供 EX 阶段使用）
    output reg         is_branch,     // 条件分支（BEQ 等，EX 判断是否跳）
    output reg  [2:0]  branch_funct3, // 分支类型
    output reg         is_jmp,        // 无条件跳转（JAL/JALR）
    output reg  [31:0] jmp_addr,      // 跳转目标地址

    // PC 传递给后级
    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4,      // pc+4（用于 JAL/JALR 写 rd）

    // 是否为 Load（供 Hazard Unit 检测 Load-use）
    output reg         is_load,

    // 指令无效标志（未知指令或 rst）
    output reg         inst_invalid
);

    // -------------------------------------------------------
    // 指令字段拆解（组合逻辑）
    // -------------------------------------------------------
    wire [6:0] opcode = inst[6:0];
    wire [4:0] rd     = inst[11:7];
    wire [2:0] funct3 = inst[14:12];
    wire [4:0] rs1    = inst[19:15];
    wire [4:0] rs2    = inst[24:20];
    wire [6:0] funct7 = inst[31:25];

    // I 型立即数（符号扩展 12 位）
    wire [31:0] imm_I = {{20{inst[31]}}, inst[31:20]};
    // S 型立即数（符号扩展 12 位）
    wire [31:0] imm_S = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    // B 型立即数（符号扩展 13 位，最低位为 0）
    wire [31:0] imm_B = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    // U 型立即数（高 20 位，低 12 位为 0）
    wire [31:0] imm_U = {inst[31:12], 12'b0};
    // J 型立即数（符号扩展 21 位，最低位为 0）
    wire [31:0] imm_J = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

    // -------------------------------------------------------
    // 前递选择（组合逻辑）：EX > MEM > RegFile
    // -------------------------------------------------------
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;

    // rs1 前递选择
    assign rs1_data = (fwd_ex_wen  && (fwd_ex_waddr  == rs1) && (rs1 != 5'd0)) ? fwd_ex_wdata  :
                      (fwd_mem_wen && (fwd_mem_waddr == rs1) && (rs1 != 5'd0)) ? fwd_mem_wdata :
                      reg_rdata1;

    // rs2 前递选择
    assign rs2_data = (fwd_ex_wen  && (fwd_ex_waddr  == rs2) && (rs2 != 5'd0)) ? fwd_ex_wdata  :
                      (fwd_mem_wen && (fwd_mem_waddr == rs2) && (rs2 != 5'd0)) ? fwd_mem_wdata :
                      reg_rdata2;

    // -------------------------------------------------------
    // 完整译码逻辑（组合逻辑 always @(*)）
    // -------------------------------------------------------
    always @(*) begin
        // ---- 默认值（避免 latch） ----
        reg_raddr1    = 5'd0;
        reg_raddr2    = 5'd0;
        alu_op        = `ALU_ADD;
        alu_src1      = 32'd0;
        alu_src2      = 32'd0;
        mem_ren       = 1'b0;
        mem_wen       = 1'b0;
        mem_funct3    = 3'b000;
        mem_wdata     = 32'd0;
        reg_wen       = 1'b0;
        reg_waddr     = 5'd0;
        is_branch     = 1'b0;
        branch_funct3 = 3'b000;
        is_jmp        = 1'b0;
        jmp_addr      = 32'd0;
        pc_out        = pc;
        pc_plus4      = pc + 32'd4;
        is_load       = 1'b0;
        inst_invalid  = 1'b0;

        if (rst) begin
            // 复位时输出全部无效
            inst_invalid = 1'b1;
        end else begin
            case (opcode)
                // ============================================
                // R 型指令：ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND
                // ============================================
                `OPCODE_R: begin
                    reg_raddr1 = rs1;
                    reg_raddr2 = rs2;
                    reg_waddr  = rd;
                    reg_wen    = 1'b1;
                    mem_ren    = 1'b0;
                    mem_wen    = 1'b0;
                    is_branch  = 1'b0;
                    is_jmp     = 1'b0;
                    alu_src1   = rs1_data;
                    alu_src2   = rs2_data;

                    case (funct3)
                        `F3_ADD_SUB: begin
                            if (funct7 == `F7_NORMAL)
                                alu_op = `ALU_ADD;  // ADD
                            else if (funct7 == `F7_ALT)
                                alu_op = `ALU_SUB;  // SUB
                            else
                                inst_invalid = 1'b1;
                        end
                        `F3_SLL:    alu_op = `ALU_SLL;   // SLL
                        `F3_SLT:    alu_op = `ALU_SLT;   // SLT
                        `F3_SLTU:   alu_op = `ALU_SLTU;  // SLTU
                        `F3_XOR:    alu_op = `ALU_XOR;   // XOR
                        `F3_SRL_SRA: begin
                            if (funct7 == `F7_NORMAL)
                                alu_op = `ALU_SRL;  // SRL
                            else if (funct7 == `F7_ALT)
                                alu_op = `ALU_SRA;  // SRA
                            else
                                inst_invalid = 1'b1;
                        end
                        `F3_OR:     alu_op = `ALU_OR;    // OR
                        `F3_AND:    alu_op = `ALU_AND;   // AND
                        default:    inst_invalid = 1'b1;
                    endcase
                end

                // ============================================
                // I 型算术指令：ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI
                // ============================================
                `OPCODE_I_ALU: begin
                    reg_raddr1 = rs1;
                    reg_waddr  = rd;
                    reg_wen    = 1'b1;
                    mem_ren    = 1'b0;
                    mem_wen    = 1'b0;
                    is_branch  = 1'b0;
                    is_jmp     = 1'b0;
                    alu_src1   = rs1_data;

                    case (funct3)
                        `F3_ADD_SUB: begin
                            // ADDI：符号扩展立即数
                            alu_op   = `ALU_ADD;
                            alu_src2 = imm_I;
                        end
                        `F3_SLT: begin
                            // SLTI：有符号比较
                            alu_op   = `ALU_SLT;
                            alu_src2 = imm_I;
                        end
                        `F3_SLTU: begin
                            // SLTIU：无符号比较（立即数符号扩展后按无符号处理）
                            alu_op   = `ALU_SLTU;
                            alu_src2 = imm_I;
                        end
                        `F3_XOR: begin
                            // XORI
                            alu_op   = `ALU_XOR;
                            alu_src2 = imm_I;
                        end
                        `F3_OR: begin
                            // ORI
                            alu_op   = `ALU_OR;
                            alu_src2 = imm_I;
                        end
                        `F3_AND: begin
                            // ANDI
                            alu_op   = `ALU_AND;
                            alu_src2 = imm_I;
                        end
                        `F3_SLL: begin
                            // SLLI：移位量为 imm[4:0]，funct7 必须为 0
                            if (funct7 == `F7_NORMAL) begin
                                alu_op   = `ALU_SLL;
                                alu_src2 = {27'd0, inst[24:20]};  // shamt
                            end else begin
                                inst_invalid = 1'b1;
                            end
                        end
                        `F3_SRL_SRA: begin
                            // SRLI / SRAI：由 funct7[5] 区分
                            alu_src2 = {27'd0, inst[24:20]};      // shamt
                            if (funct7 == `F7_NORMAL)
                                alu_op = `ALU_SRL;  // SRLI
                            else if (funct7 == `F7_ALT)
                                alu_op = `ALU_SRA;  // SRAI
                            else
                                inst_invalid = 1'b1;
                        end
                        default: inst_invalid = 1'b1;
                    endcase
                end

                // ============================================
                // I 型 Load：LB/LH/LW/LBU/LHU
                // ============================================
                `OPCODE_I_LOAD: begin
                    reg_raddr1 = rs1;
                    reg_waddr  = rd;
                    reg_wen    = 1'b1;
                    mem_ren    = 1'b1;
                    mem_wen    = 1'b0;
                    is_load    = 1'b1;
                    is_branch  = 1'b0;
                    is_jmp     = 1'b0;
                    // ALU 计算访存地址：rs1 + sext(imm_I)
                    alu_op     = `ALU_ADD;
                    alu_src1   = rs1_data;
                    alu_src2   = imm_I;
                    mem_funct3 = funct3;
                end

                // ============================================
                // S 型 Store：SB/SH/SW
                // ============================================
                `OPCODE_S: begin
                    reg_raddr1 = rs1;
                    reg_raddr2 = rs2;
                    reg_wen    = 1'b0;
                    mem_ren    = 1'b0;
                    mem_wen    = 1'b1;
                    is_branch  = 1'b0;
                    is_jmp     = 1'b0;
                    // ALU 计算访存地址：rs1 + sext(imm_S)
                    alu_op     = `ALU_ADD;
                    alu_src1   = rs1_data;
                    alu_src2   = imm_S;
                    // Store 写数据（前递选择后的 rs2）
                    mem_wdata  = rs2_data;
                    mem_funct3 = funct3;
                end

                // ============================================
                // B 型条件分支：BEQ/BNE/BLT/BGE/BLTU/BGEU
                // ============================================
                `OPCODE_B: begin
                    reg_raddr1    = rs1;
                    reg_raddr2    = rs2;
                    reg_wen       = 1'b0;
                    mem_ren       = 1'b0;
                    mem_wen       = 1'b0;
                    is_branch     = 1'b1;
                    is_jmp        = 1'b0;
                    branch_funct3 = funct3;
                    // 分支目标地址：pc + sext(imm_B)
                    jmp_addr      = pc + imm_B;
                    // 将 rs1/rs2 传给 EX 阶段进行比较
                    alu_src1      = rs1_data;
                    alu_src2      = rs2_data;
                    alu_op        = `ALU_SUB;  // EX 阶段直接比较，alu_op 仅参考
                end

                // ============================================
                // U 型 LUI：rd = imm_U
                // ============================================
                `OPCODE_U_LUI: begin
                    reg_waddr  = rd;
                    reg_wen    = 1'b1;
                    mem_ren    = 1'b0;
                    mem_wen    = 1'b0;
                    is_branch  = 1'b0;
                    is_jmp     = 1'b0;
                    // COPY_A：result = src1 = {inst[31:12], 12'b0}
                    alu_op     = `ALU_COPY_A;
                    alu_src1   = imm_U;
                    alu_src2   = 32'd0;
                end

                // ============================================
                // U 型 AUIPC：rd = pc + imm_U
                // ============================================
                `OPCODE_U_AUIPC: begin
                    reg_waddr  = rd;
                    reg_wen    = 1'b1;
                    mem_ren    = 1'b0;
                    mem_wen    = 1'b0;
                    is_branch  = 1'b0;
                    is_jmp     = 1'b0;
                    // ADD：result = pc + {inst[31:12], 12'b0}
                    alu_op     = `ALU_ADD;
                    alu_src1   = pc;
                    alu_src2   = imm_U;
                end

                // ============================================
                // J 型 JAL：rd = pc+4，pc = pc + sext(imm_J)
                // ============================================
                `OPCODE_J_JAL: begin
                    reg_waddr  = rd;
                    reg_wen    = 1'b1;
                    mem_ren    = 1'b0;
                    mem_wen    = 1'b0;
                    is_branch  = 1'b0;
                    is_jmp     = 1'b1;
                    // ALU 结果 = pc+4（写入 rd）
                    alu_op     = `ALU_COPY_A;
                    alu_src1   = pc + 32'd4;
                    alu_src2   = 32'd0;
                    // 跳转目标：pc + sext(imm_J)
                    jmp_addr   = pc + imm_J;
                end

                // ============================================
                // I 型 JALR：rd = pc+4，pc = (rs1 + sext(imm_I)) & ~1
                // ============================================
                `OPCODE_I_JALR: begin
                    reg_raddr1 = rs1;
                    reg_waddr  = rd;
                    reg_wen    = 1'b1;
                    mem_ren    = 1'b0;
                    mem_wen    = 1'b0;
                    is_branch  = 1'b0;
                    is_jmp     = 1'b1;
                    // ALU 结果 = pc+4（写入 rd）
                    alu_op     = `ALU_COPY_A;
                    alu_src1   = pc + 32'd4;
                    alu_src2   = 32'd0;
                    // 跳转目标：(rs1 + sext(imm_I)) & ~32'h1（清最低位）
                    jmp_addr   = (rs1_data + imm_I) & ~32'h1;
                end

                // ============================================
                // FENCE：当 NOP 处理（不生成访存）
                // ============================================
                `OPCODE_FENCE: begin
                    // 全部控制信号为默认 0，相当于 NOP
                end

                // ============================================
                // SYSTEM（ECALL/EBREAK/CSR）：当 NOP 处理
                // ============================================
                `OPCODE_SYS: begin
                    // 全部控制信号为默认 0，相当于 NOP
                end

                // ============================================
                // 未知指令：标记无效
                // ============================================
                default: begin
                    inst_invalid = 1'b1;
                end
            endcase
        end
    end

endmodule

`endif // ID_SV
