// =============================================================
// 文件：rtl/core/if_id.sv
// 描述：IF/ID 流水线寄存器
//       - 优先级：rst > flush > hold > 正常传递
//       - flush：将指令置为 NOP，PC 置 0（冲刷控制冒险气泡）
//       - hold：保持当前值不变（数据冒险暂停）
// =============================================================
`ifndef IF_ID_SV
`define IF_ID_SV

`include "core_define.svh"

module IFID (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,    // 控制冒险时清空（置 NOP）
    input  wire        hold,     // 数据冒险时保持当前值

    // 输入（来自 IF 阶段）
    input  wire [31:0] if_pc,
    input  wire [31:0] if_inst,

    // 输出（到 ID 阶段）
    output reg  [31:0] id_pc,
    output reg  [31:0] id_inst
);

    // -------------------------------------------------------
    // 流水线寄存器更新逻辑（同步，posedge clk）
    // 优先级：复位 > 冲刷 > 保持 > 正常传递
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            // 复位：清空流水线寄存器
            id_pc   <= 32'd0;
            id_inst <= `INST_NOP;
        end else if (flush) begin
            // 冲刷：插入 NOP 气泡（控制冒险——分支/跳转已判定）
            id_pc   <= 32'd0;
            id_inst <= `INST_NOP;
        end else if (hold) begin
            // 保持：不更新（Load-use 数据冒险暂停）
            id_pc   <= id_pc;
            id_inst <= id_inst;
        end else begin
            // 正常传递：锁存 IF 阶段的 PC 和指令
            id_pc   <= if_pc;
            id_inst <= if_inst;
        end
    end

endmodule

`endif // IF_ID_SV
