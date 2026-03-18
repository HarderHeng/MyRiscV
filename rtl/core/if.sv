// =============================================================
// 文件：rtl/core/if.sv
// 描述：IF 阶段 —— PC 寄存器维护，输出取指地址
//       - 同步高有效复位（posedge clk，rst=1 有效）
//       - 优先级：rst > hold > jmp > pc+4
// =============================================================
`ifndef IF_SV
`define IF_SV

`include "core_define.svh"

module InstructionFetch (
    input  wire        clk,
    input  wire        rst,

    // 跳转信号（来自 EX 阶段，jmp 和 jmp_addr 同周期有效）
    input  wire        jmp,
    input  wire [31:0] jmp_addr,

    // 暂停信号（Load-use 冒险或调试 halt）
    input  wire        hold,

    // PC 输出（同时也是 IRAM 的取指地址）
    output reg  [31:0] pc
);

    // -------------------------------------------------------
    // PC 更新逻辑（同步，posedge clk）
    // 优先级：复位 > 暂停保持 > 跳转 > 顺序 +4
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            // 复位：PC 跳到 CPU 启动地址
            pc <= `CpuResetAddr;
        end else if (hold) begin
            // 暂停：PC 保持不变（Load-use 或调试 halt）
            pc <= pc;
        end else if (jmp) begin
            // 跳转：更新为目标地址（JAL/JALR/分支成立）
            pc <= jmp_addr;
        end else begin
            // 正常顺序执行：PC+4
            pc <= pc + 32'd4;
        end
    end

endmodule

`endif // IF_SV
