`include "core_define.svh"
module InstrucionFetch(
    //时钟信号、复位信号
    input wire clk,
    input wire rst,
    //跳转信号和跳转地址
    input wire jmp,
    input wire[`InstAddrWidth] jmp_addr,
    //暂停流水线信号
    input wire hold_flag,
    //PC寄存器输出信号
    output reg[`InstAddrWidth] pc,
);

    always @(posedge clk) begin
        if (rst == 1'b1) begin
            pc = `CpuResetAddr;
        end else if (hold_flag == 1'b1) begin
            pc = pc;
        end else if (jmp == 1'b1) begin
            pc = jmp_addr;
        end else begin
            pc = pc + 4;
        end

    end

endmodule
