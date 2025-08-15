
`inlcude "alu.svh"
module ALU(
    input wire[3:0] alu_op,
    input wire[31:0] alu_src1,
    input wire[31:0] alu_src2,

    output reg[31:0] alu_out
);

    always @(*) begin
        case(alu_op)
            `ALU_OP_ADD: begin
                alu_out = alu_src1 + alu_src2;
            end
            `ALU_OP_SUB: begin
                alu_out = alu_src1 - alu_src2;
            end
            `ALU_OP_XOR: begin
                alu_out = alu_src1 ^ alu_src2;
            end
            `ALU_OP_OR: begin
                alu_out = alu_src1 | alu_src2;
            end
            `ALU_OP_AND: begin
                alu_out = alu_src1 & alu_src2;
            end
            `ALU_OP_SLL: begin
                alu_out = alu_src1 << alu_src2;
            end
            `ALU_OP_SRA: begin
                alu_out = alu_src1 >> alu_src2;
            end
            `ALU_OP_SRL: begin
                alu_out = $signed(alu_src1) >>> alu_src2;
            end
            `ALU_OP_SLT: begin
                alu_out = $signed(alu_src1) < $signed(alu_src2) ? 1 : 0;
            end
            `ALU_OP_SLTU: begin
                alu_out = (alu_src1 < alu_src2) ? 1 : 0;
            end
        endcase
    end
endmodule
