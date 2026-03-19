// =============================================================
// 文件：rtl/alu/alu.sv
// 描述：ALU 模块（纯组合逻辑，无时钟）
//       支持 RV32I 所有算术/逻辑/移位/比较操作
// =============================================================
`ifndef ALU_SV
`define ALU_SV

`include "alu.svh"

module RvALU (
    input  wire [3:0]  alu_op,   // ALU 操作码
    input  wire [31:0] src1,     // 操作数1
    input  wire [31:0] src2,     // 操作数2
    output reg  [31:0] result    // 运算结果
);

    always @(*) begin
        case (alu_op)
            // 加法
            `ALU_ADD:    result = src1 + src2;
            // 减法
            `ALU_SUB:    result = src1 - src2;
            // 按位异或
            `ALU_XOR:    result = src1 ^ src2;
            // 按位或
            `ALU_OR:     result = src1 | src2;
            // 按位与
            `ALU_AND:    result = src1 & src2;
            // 逻辑左移（移位量取低5位）
            `ALU_SLL:    result = src1 << src2[4:0];
            // 逻辑右移（无符号）
            `ALU_SRL:    result = src1 >> src2[4:0];
            // 算术右移（有符号，保留符号位）
            `ALU_SRA:    result = $signed(src1) >>> src2[4:0];
            // 有符号小于比较
            `ALU_SLT:    result = ($signed(src1) < $signed(src2)) ? 32'd1 : 32'd0;
            // 无符号小于比较
            `ALU_SLTU:   result = (src1 < src2) ? 32'd1 : 32'd0;
            // 直通 src1（用于 LUI：src1=imm<<12，src2=0）
            `ALU_COPY_A: result = src1;
            // 直通 src2（保留）
            `ALU_COPY_B: result = src2;
            // 未知操作码：输出 0
            default:     result = 32'd0;
        endcase
    end

endmodule

`endif // ALU_SV
