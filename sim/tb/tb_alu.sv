`timescale 1ns/1ps
// ============================================================
//  ALU 单元测试 Testbench
//  覆盖所有 12 种 ALU 操作码（ADD/SUB/XOR/OR/AND/SLL/SRL/SRA/SLT/SLTU/COPY_A/COPY_B）
//  通过 $display 输出测试结果，通过 $error 报告失败
// ============================================================
`include "alu.svh"

module tb_alu;

// DUT 信号
reg  [3:0]  alu_op;
reg  [31:0] src1;
reg  [31:0] src2;
wire [31:0] result;

// 期望值寄存器
reg  [31:0] expected;

// 测试计数
integer pass_cnt;
integer fail_cnt;

// DUT 例化
RvALU u_alu (
    .alu_op (alu_op),
    .src1   (src1),
    .src2   (src2),
    .result (result)
);

// 辅助任务：检查结果
task check;
    input [3:0]  op;
    input [31:0] a, b, exp;
    input [127:0] name;  // 操作名（字符串）
    begin
        alu_op = op;
        src1   = a;
        src2   = b;
        #1;  // 等待组合逻辑稳定
        if (result === exp) begin
            pass_cnt = pass_cnt + 1;
        end else begin
            fail_cnt = fail_cnt + 1;
            $error("[FAIL] %s: src1=0x%08X src2=0x%08X expected=0x%08X got=0x%08X",
                   name, a, b, exp, result);
        end
    end
endtask

initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    $display("=== ALU Unit Test ===");

    // --------------------------------------------------------
    // ADD
    // --------------------------------------------------------
    check(`ALU_ADD, 32'h0000_0001, 32'h0000_0001, 32'h0000_0002, "ADD norm  ");
    check(`ALU_ADD, 32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0000, "ADD wrap  ");  // 溢出回绕
    check(`ALU_ADD, 32'h8000_0000, 32'h8000_0000, 32'h0000_0000, "ADD ovfl  ");
    check(`ALU_ADD, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, "ADD zero  ");

    // --------------------------------------------------------
    // SUB
    // --------------------------------------------------------
    check(`ALU_SUB, 32'h0000_0005, 32'h0000_0003, 32'h0000_0002, "SUB norm  ");
    check(`ALU_SUB, 32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF, "SUB wrap  ");  // 负结果
    check(`ALU_SUB, 32'hABCD_1234, 32'hABCD_1234, 32'h0000_0000, "SUB self  ");

    // --------------------------------------------------------
    // XOR
    // --------------------------------------------------------
    check(`ALU_XOR, 32'hFFFF_0000, 32'h0000_FFFF, 32'hFFFF_FFFF, "XOR comp  ");
    check(`ALU_XOR, 32'hAAAA_AAAA, 32'hAAAA_AAAA, 32'h0000_0000, "XOR self  ");
    check(`ALU_XOR, 32'h1234_5678, 32'h0000_0000, 32'h1234_5678, "XOR zero  ");

    // --------------------------------------------------------
    // OR
    // --------------------------------------------------------
    check(`ALU_OR,  32'hFFFF_0000, 32'h0000_FFFF, 32'hFFFF_FFFF, "OR   full ");
    check(`ALU_OR,  32'h0000_0000, 32'h0000_0000, 32'h0000_0000, "OR   zero ");

    // --------------------------------------------------------
    // AND
    // --------------------------------------------------------
    check(`ALU_AND, 32'hFFFF_FFFF, 32'h0F0F_0F0F, 32'h0F0F_0F0F, "AND mask  ");
    check(`ALU_AND, 32'hFFFF_FFFF, 32'h0000_0000, 32'h0000_0000, "AND zero  ");

    // --------------------------------------------------------
    // SLL（逻辑左移）
    // --------------------------------------------------------
    check(`ALU_SLL, 32'h0000_0001, 32'h0000_0001, 32'h0000_0002, "SLL by1   ");
    check(`ALU_SLL, 32'h0000_0001, 32'h0000_001F, 32'h8000_0000, "SLL by31  ");
    check(`ALU_SLL, 32'h0000_0001, 32'h0000_0020, 32'h0000_0001, "SLL by32  ");  // mod32
    check(`ALU_SLL, 32'hFFFF_FFFF, 32'h0000_0008, 32'hFFFF_FF00, "SLL mask  ");

    // --------------------------------------------------------
    // SRL（逻辑右移）
    // --------------------------------------------------------
    check(`ALU_SRL, 32'h8000_0000, 32'h0000_0001, 32'h4000_0000, "SRL by1   ");
    check(`ALU_SRL, 32'hFFFF_FFFF, 32'h0000_0008, 32'h00FF_FFFF, "SRL by8   ");
    check(`ALU_SRL, 32'h8000_0000, 32'h0000_001F, 32'h0000_0001, "SRL by31  ");

    // --------------------------------------------------------
    // SRA（算术右移，符号扩展）
    // --------------------------------------------------------
    check(`ALU_SRA, 32'h8000_0000, 32'h0000_0001, 32'hC000_0000, "SRA neg1  ");  // 负数右移
    check(`ALU_SRA, 32'hFFFF_FFFF, 32'h0000_0008, 32'hFFFF_FFFF, "SRA neg8  ");  // -1 右移
    check(`ALU_SRA, 32'h4000_0000, 32'h0000_0001, 32'h2000_0000, "SRA pos1  ");  // 正数右移
    check(`ALU_SRA, 32'h8000_0000, 32'h0000_001F, 32'hFFFF_FFFF, "SRA by31  ");  // 负数右移31

    // --------------------------------------------------------
    // SLT（有符号比较，true=1）
    // --------------------------------------------------------
    check(`ALU_SLT, 32'h0000_0001, 32'h0000_0002, 32'h0000_0001, "SLT pos<p ");
    check(`ALU_SLT, 32'h0000_0002, 32'h0000_0001, 32'h0000_0000, "SLT pos>p ");
    check(`ALU_SLT, 32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0001, "SLT neg<p ");  // -1 < 1
    check(`ALU_SLT, 32'h0000_0001, 32'hFFFF_FFFF, 32'h0000_0000, "SLT pos>n ");  // 1 > -1
    check(`ALU_SLT, 32'h0000_0001, 32'h0000_0001, 32'h0000_0000, "SLT equal ");

    // --------------------------------------------------------
    // SLTU（无符号比较）
    // --------------------------------------------------------
    check(`ALU_SLTU, 32'h0000_0001, 32'h0000_0002, 32'h0000_0001, "SLTU <    ");
    check(`ALU_SLTU, 32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0000, "SLTU big>s");  // 大无符号数
    check(`ALU_SLTU, 32'h0000_0000, 32'hFFFF_FFFF, 32'h0000_0001, "SLTU 0<max");

    // --------------------------------------------------------
    // COPY_A（LUI 用：直通 src1）
    // --------------------------------------------------------
    check(`ALU_COPY_A, 32'hDEAD_BEEF, 32'h1234_5678, 32'hDEAD_BEEF, "COPY_A    ");
    check(`ALU_COPY_A, 32'h1000_0000, 32'h0000_0000, 32'h1000_0000, "COPY_A lui");

    // --------------------------------------------------------
    // COPY_B（直通 src2）
    // --------------------------------------------------------
    check(`ALU_COPY_B, 32'hDEAD_BEEF, 32'h1234_5678, 32'h1234_5678, "COPY_B    ");

    // --------------------------------------------------------
    // 汇总
    // --------------------------------------------------------
    $display("=== Results: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
        $display("ALL PASS");
    else
        $display("SOME TESTS FAILED");

    $finish;
end

endmodule
