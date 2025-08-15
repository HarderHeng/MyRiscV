`include "core_define.svh"
`include "../alu/alu.svh"
module InstructionDecode(
    
    input wire rst, //复位信号
    
    input wire[`InstWidth] instruction_in, //输入指令
    
    input wire[`DataWidth] reg1_rdata, //读寄存器堆
    input wire[`DataWidth] reg2_rdata, //读寄存器堆
    input wire[`DataWidth] csr_rdata, //读csr寄存器堆

    output reg ex_en, //是否需要执行

    output reg ex_alu,
    output reg ex_mem,
    output reg ex_wb,
    output reg ex_jmp,

    output reg[3:0] alu_op,
    output reg mem_op,

    output reg[`RegAddrWidth] reg1_raddr, //读取通用寄存器1地址
    output reg[`RegAddrWidth] reg2_raddr, //读取通用寄存器2地址
    output reg[`RegAddrWidth] reg_waddr, //写入目标寄存器地址
    output reg[`CsrAddrWidth] csr_raddr, //读取csr寄存器地址

    output reg[`DataWidth] alu_src1,
    output reg[`DataWidth] alu_src2,
    output reg[`DataWidth] branch_target,
);

    wire[6:0] opcode = instruction_in[6:0];
    wire[4:0] rd = instruction_in[11:7];
    wire[2:0] funct3 = instruction_in[14:12];
    wire[4:0] rs1 = instruction_in[19:15];
    wire[4:0] rs2 = instruction_in[24:20];
    wire[6:0] funct7 = instruction_in[31:25];

    wire[11:0] imm_I = instruction_in[31:20]; //I型指令的imm
    always @(*) begin

        ex_en = 1'b1; //默认是有效指令

        ex_alu = 1'b0;
        ex_mem = 1'b0;
        ex_wb = 1'b0;
        ex_jmp = 1'b0;
        //默认全部不开启

        alu_op = 4'b0000;
        mem_op = 1'b0;
        reg1_raddr = 0;

        case (opcode)
            `INST_TYPE_R: begin
                ex_alu = 1'b1; //默认有ALU操作
                reg1_raddr = rs1;
                reg2_raddr = rs2;
                reg_waddr = rd;
                alu_src1 = reg1_rdata;
                alu_src2 = reg2_rdata;
                case(funct3)
                    `INST_FUNCT3_ADD_SUB: begin
                        if(funct7 == `INST_FUNCT7_ADD) begin
                            alu_op = `ALU_OP_ADD; //加法指令
                        end else if(funct7 == `INST_FUNCT7_SUB) begin
                            alu_op = `ALU_OP_SUB; //减法指令
                        end else begin
                            ex_en = 1'b0; //指令失效
                        end
                    end
                    `INST_FUNCT3_AND: begin
                        alu_op = `ALU_OP_AND; //按位与
                    end
                    `INST_FUNCT3_OR: begin
                        alu_op = `ALU_OP_OR; //按位或
                    end
                    `INST_FUNCT3_XOR: begin
                        alu_op = `ALU_OP_XOR; //按位异或
                    end
                    `INST_FUNCT3_SLL: begin
                        alu_op = `ALU_OP_SLL; //逻辑左移
                    end
                    `INST_FUNCT3_SRL_SRA: begin
                        if(funct7 == `INST_FUNCT7_SRL) begin
                            alu_op = `ALU_OP_SRL; //逻辑左移
                        end else if(funct7 == `INST_FUNCT7_SRA) begin
                            alu_op = `ALU_OP_SRA; //算数左移
                        end else begin
                            ex_en = 0; //指令失效
                        end
                    end
                    `INST_FUNCT3_SLT: begin
                        alu_op = `ALU_OP_SLT; //大小比较
                    end
                    `INST_FUNCT3_SLTU: begin
                        alu_op = `ALU_OP_SLTU; //无符号数大小比较
                    default: begin
                        ex_en = 1'b0; //指令失效
                    end
                endcase
            `INST_TYPE_I: begin
                ex_alu = 1'b1; //默认有alu操作
                reg1_raddr = rs1;
                reg_waddr = rd;
                alu_src1 = reg1_rdata;
                case(funct3)
                    `INST_FUNCT3_ADDI: begin
                        alu_op = `ALU_OP_ADD;
                        alu_src2 = {{20{imm_I[12]}}, imm_I};
                    end
                    `INST_FUNCT3_ANDI: begin
                        alu_op = `ALU_OP_AND;
                        alu_src2 = {{20{imm_I[12]}}, imm_I};
                    end
                    `INST_FUNCT3_ORI: begin
                        alu_op = `ALU_OP_OR;
                        alu_src2 = {{20{imm_I[12]}}, imm_I};
                    end
                    `INST_FUNCT3_XORI: begin
                        alu_op = `ALU_OP_XOR;
                        alu_src2 = {{20{imm_I[12]}}, imm_I};
                    end
                    `INST_FUNCT3_SLLI: begin
                        if(funct7 == `INST_FUNCT7_SLLI) begin
                            alu_op = `ALU_OP_SLL;
                            alu_src2 = imm_I[4:0]; //保证为正数不考虑符号扩展
                        end else begin
                            ex_en = 1'b0;
                        end
                    end
                    `INST_FUNCT3_SRLI_SRAI: begin
                        alu_src2 = {imm_I[4:0]};
                        if(funct7 == `INST_FUNCT7_SRLI) begin
                            alu_op = `ALU_OP_SRL;
                        end else if(funct7 == `INST_FUNCT7_SRAI) begin
                            alu_op = `ALU_OP_SRA;
                        end else begin
                            ex_en = 1'b0;
                        end
                    end
                    `INST_FUNCT3_SLTI: begin
                        alu_op = `ALU_OP_SLT;
                        alu_src2 = imm_I;
                    end
                    `INST_FUNCT3_SLTIU: begin
                        alu_op = `ALU_OP_SLTU;
                        alu_src2 = imm_I;
                    end
                    default: begin
                        ex_en = 1'b0;
                    end
                endcase
            `INST_TYPE_I_L: begin
                ex_alu = 1'b1; //ALU操作计算Load地址
                alu_op = `ALU_OP_ADD; //ALU加法
                ex_mem = 1'b1;
                mem_op = 
                reg1_raddr = rs1;
                reg_waddr = rd;
                alu_src1 = reg1_rdata;
    end