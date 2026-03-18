// =============================================================
// 文件：rtl/core/hazard.sv
// 描述：冒险检测单元（Hazard Detection Unit）
//       - 检测 Load-use 数据冒险：EX 阶段的 Load 指令目标寄存器
//         与 ID 阶段的源寄存器冲突时，插入一拍气泡（stall）
//       - 检测控制冒险：EX 阶段发出跳转信号时，冲刷流水线（flush）
// =============================================================
`ifndef HAZARD_SV
`define HAZARD_SV

`include "core_define.svh"

module HazardUnit (
    // EX 阶段信息（当前在 EX 的是否为 Load 指令及其目标寄存器）
    input  wire        ex_is_load,
    input  wire [4:0]  ex_reg_waddr,

    // ID 阶段读的源寄存器地址
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,

    // Load-use 冒险标志
    // =1 时：PC hold，IF/ID hold，ID/EX flush（插入气泡）
    output wire        load_use_stall,

    // 来自 EX 的跳转信号（分支成立或无条件跳转）
    input  wire        ex_jmp,

    // 分支/跳转冲刷标志
    // =1 时：IF/ID flush，ID/EX flush（冲刷已取入但不该执行的指令）
    output wire        branch_flush
);

    // -------------------------------------------------------
    // Load-use 冒险检测
    // 条件：EX 阶段是 Load 指令，且目标寄存器与 ID 阶段读的
    //       rs1 或 rs2 相同，并且目标寄存器不是 x0
    // -------------------------------------------------------
    assign load_use_stall = ex_is_load &&
                            (ex_reg_waddr != 5'd0) &&
                            ((ex_reg_waddr == id_rs1) || (ex_reg_waddr == id_rs2));

    // -------------------------------------------------------
    // 控制冒险冲刷
    // 当 EX 阶段产生实际跳转时（分支成立或 JAL/JALR），需要
    // 冲刷已经进入 IF 和 ID 阶段的错误路径指令
    // -------------------------------------------------------
    assign branch_flush = ex_jmp;

endmodule

`endif // HAZARD_SV
