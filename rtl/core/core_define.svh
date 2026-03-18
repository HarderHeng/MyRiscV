`ifndef CORE_DEFINE_SVH
`define CORE_DEFINE_SVH

// ============================================================
//  基础位宽定义
// ============================================================
`define DataWidth       31:0    // 数据总线宽度
`define AddrWidth       31:0    // 地址总线宽度
`define InstWidth       31:0    // 指令字宽度
`define InstAddrWidth   31:0    // 指令地址宽度
`define RegAddrWidth    4:0     // 通用寄存器地址（5位，32个寄存器）
`define CsrAddrWidth    11:0    // CSR 地址宽度

// CPU 复位后取指地址
`define CpuResetAddr    32'h80000000

// ============================================================
//  Opcode 定义（instruction[6:0]）
// ============================================================
`define OPCODE_R        7'b0110011   // R型
`define OPCODE_I_ALU    7'b0010011   // I型算术
`define OPCODE_I_LOAD   7'b0000011   // I型 Load
`define OPCODE_I_JALR   7'b1100111   // JALR
`define OPCODE_S        7'b0100011   // S型 Store
`define OPCODE_B        7'b1100011   // B型分支
`define OPCODE_U_LUI    7'b0110111   // LUI
`define OPCODE_U_AUIPC  7'b0010111   // AUIPC
`define OPCODE_J_JAL    7'b1101111   // JAL
`define OPCODE_FENCE    7'b0001111   // FENCE（当前当 NOP 处理）
`define OPCODE_SYS      7'b1110011   // SYSTEM（ECALL/EBREAK/CSR）

// ============================================================
//  funct3 定义
// ============================================================
// R型 / I型算术
`define F3_ADD_SUB  3'b000
`define F3_SLL      3'b001
`define F3_SLT      3'b010
`define F3_SLTU     3'b011
`define F3_XOR      3'b100
`define F3_SRL_SRA  3'b101
`define F3_OR       3'b110
`define F3_AND      3'b111

// Load
`define F3_LB       3'b000
`define F3_LH       3'b001
`define F3_LW       3'b010
`define F3_LBU      3'b100
`define F3_LHU      3'b101

// Store
`define F3_SB       3'b000
`define F3_SH       3'b001
`define F3_SW       3'b010

// Branch
`define F3_BEQ      3'b000
`define F3_BNE      3'b001
`define F3_BLT      3'b100
`define F3_BGE      3'b101
`define F3_BLTU     3'b110
`define F3_BGEU     3'b111

// funct7
`define F7_NORMAL   7'b0000000
`define F7_ALT      7'b0100000   // SUB / SRA / SRAI

// ============================================================
//  mem_op 编码（MEM 阶段 funct3 直接传递）
//  用于 Load/Store 的字节粒度控制
//  MEM 阶段通过 {mem_wen, funct3[2:0]} 判断访问类型
// ============================================================

// ============================================================
//  MUX 选择码：ALU 操作数来源
// ============================================================
`define ALU_SRC_REG     1'b0    // 来自寄存器堆
`define ALU_SRC_IMM     1'b1    // 来自立即数

// ============================================================
//  NOP 指令编码（addi x0, x0, 0）
// ============================================================
`define INST_NOP        32'h0000_0013

`endif // CORE_DEFINE_SVH
