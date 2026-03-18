`ifndef ALU_SVH
`define ALU_SVH

// ALU 操作码（4位）
`define ALU_ADD     4'd0
`define ALU_SUB     4'd1
`define ALU_XOR     4'd2
`define ALU_OR      4'd3
`define ALU_AND     4'd4
`define ALU_SLL     4'd5
`define ALU_SRL     4'd6   // 逻辑右移
`define ALU_SRA     4'd7   // 算术右移
`define ALU_SLT     4'd8   // 有符号比较
`define ALU_SLTU    4'd9   // 无符号比较
`define ALU_COPY_A  4'd10  // 直接输出 src1（用于 LUI：src1=imm, src2=0）
`define ALU_COPY_B  4'd11  // 直接输出 src2（保留）

`endif // ALU_SVH
