`include "core_define.svh"


module if_id(
    input wire clk,
    input wire rst,

    input wire hold_flag,

    input wire[`InstAddrWidth] pc_if,
    input wire[`InstWidth] instruction_if,

    output reg[`InstAddrWidth] pc_id,
    output reg[`InstWidth] instruction_id,
);
    always @(posedge clk) begin
        if (rst == 1'b1) begin
            pc_id = 0;
            instruction_id = 0;
        end else if (hold_flag == 1'b1) begin
            pc_id = pc_id;
            instruction_id = instruction_id;
        end else begin
            pc_id = pc_if;
            instruction_id = instruction_if;
        end
    end

endmodule
