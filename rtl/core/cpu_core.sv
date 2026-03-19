// =============================================================
// 文件：rtl/core/cpu_core.sv
// 描述：RV32I 5 级流水线 CPU 核心顶层
//       流水线阶段：IF → IF/ID → ID → ID/EX → EX → EX/MEM → MEM → MEM/WB → WB
//       - WB 阶段写回直接从 MEM/WB 寄存器连到 RegFile（无独立 WB 模块）
//       - 前递（Forwarding）：EX/MEM → ID，MEM/WB（对齐后）→ ID
//       - 冒险检测：Load-use stall + 分支/跳转 flush
//       - 调试接口：halt/resume，RegFile 调试读写，PC 查询
// =============================================================
`ifndef CPU_CORE_SV
`define CPU_CORE_SV

`include "core_define.svh"

module CpuCore (
    input  wire        clk,
    input  wire        rst,

    // 指令存储器（组合读，异步）
    output wire [31:0] iram_addr,
    input  wire [31:0] iram_rdata,

    // 数据总线
    output wire [31:0] dbus_addr,
    output wire        dbus_ren,
    output wire        dbus_wen,
    output wire [3:0]  dbus_be,
    output wire [31:0] dbus_wdata,
    input  wire [31:0] dbus_rdata,

    // 调试接口（供 Debug Module 使用）
    input  wire        dbg_halt_req,    // 请求暂停流水线
    output wire        dbg_halted,      // 流水线已暂停
    input  wire        dbg_resume_req,  // 请求继续执行
    input  wire [4:0]  dbg_reg_raddr,   // 调试读寄存器地址
    output wire [31:0] dbg_reg_rdata,   // 调试读寄存器数据
    input  wire        dbg_reg_wen,     // 调试写寄存器使能
    input  wire [4:0]  dbg_reg_waddr,   // 调试写寄存器地址
    input  wire [31:0] dbg_reg_wdata,   // 调试写寄存器数据
    output wire [31:0] dbg_pc           // 当前 PC（IF 阶段）
);

    // ===========================================================
    // 调试 halt 控制逻辑
    // ===========================================================
    reg  halt_latched;  // 已捕获的 halt 状态寄存器

    always @(posedge clk) begin
        if (rst) begin
            halt_latched <= 1'b0;
        end else if (dbg_halt_req) begin
            // halt 请求：锁存 halt 状态
            halt_latched <= 1'b1;
        end else if (dbg_resume_req) begin
            // resume 请求：解除 halt
            halt_latched <= 1'b0;
        end
    end

    // 已暂停标志：dbg_halt_req 高有效或已锁存的 halt 状态
    assign dbg_halted = halt_latched | dbg_halt_req;

    // ===========================================================
    // IF 阶段：PC 寄存器
    // ===========================================================

    // 冒险控制信号（由 Hazard Unit 和调试逻辑决定）
    wire load_use_stall;    // Load-use 数据冒险暂停
    wire branch_flush;      // 分支/跳转冲刷

    // EX 阶段跳转信号（连接 EX → IF）
    wire        ex_jmp;
    wire [31:0] ex_jmp_addr;

    // IRAM 同步读等待：复位后等 1 周期；EX 跳转后等 1 周期
    // 确保 SDPB/行为模型同步输出在 IFID 寄存器采样前已稳定
    reg iram_wait;
    always @(posedge clk) begin
        if (rst)
            iram_wait <= 1'b1;
        else if (iram_wait)
            iram_wait <= 1'b0;
        else if (ex_jmp && !load_use_stall && !dbg_halted)
            iram_wait <= 1'b1;
    end

    // IF 暂停：Load-use stall 或 调试 halt 或 IRAM 等待
    wire if_hold = load_use_stall | dbg_halted | iram_wait;

    // IF/ID 冲刷：分支成立时冲刷（但 load_use_stall 优先，避免误冲刷）
    wire ifid_flush = branch_flush && !load_use_stall;

    // ID/EX 冲刷：分支成立 或 Load-use stall 时均需冲刷 ID/EX
    wire idex_flush = branch_flush || load_use_stall;

    // PC 寄存器输出
    wire [31:0] if_pc;

    InstructionFetch u_if (
        .clk      (clk),
        .rst      (rst),
        .jmp      (ex_jmp),
        .jmp_addr (ex_jmp_addr),
        .hold     (if_hold),
        .pc       (if_pc)
    );

    // 指令存储器地址 = 当前 PC（组合驱动 IRAM 地址）
    assign iram_addr = if_pc;
    assign dbg_pc    = if_pc;

    // ===========================================================
    // IF/ID 流水线寄存器
    // ===========================================================
    wire [31:0] id_pc;
    wire [31:0] id_inst;

    IFID u_if_id (
        .clk     (clk),
        .rst     (rst),
        .flush   (ifid_flush),
        .hold    (if_hold),
        .if_pc   (if_pc),      // 直接使用当前 PC（iram_wait hold 住时 PC 不推进，对齐同步读）
        .if_inst (iram_rdata),
        .id_pc   (id_pc),
        .id_inst (id_inst)
    );

    // ===========================================================
    // 寄存器堆（RegFile）
    // 读端口由 ID 阶段驱动，写端口由 WB 阶段驱动
    // ===========================================================

    // WB 阶段写回信号（来自 MEM/WB 寄存器）
    wire        wb_reg_wen;
    wire [4:0]  wb_reg_waddr;
    wire [31:0] wb_reg_wdata;

    // RegFile 读端口地址（由 ID 阶段输出）
    wire [4:0]  id_reg_raddr1;
    wire [4:0]  id_reg_raddr2;
    wire [31:0] id_reg_rdata1;
    wire [31:0] id_reg_rdata2;

    RegFile u_regfile (
        .clk        (clk),
        .rst        (rst),
        .raddr1     (id_reg_raddr1),
        .rdata1     (id_reg_rdata1),
        .raddr2     (id_reg_raddr2),
        .rdata2     (id_reg_rdata2),
        .wen        (wb_reg_wen),
        .waddr      (wb_reg_waddr),
        .wdata      (wb_reg_wdata),
        .dbg_raddr  (dbg_reg_raddr),
        .dbg_rdata  (dbg_reg_rdata),
        .dbg_wen    (dbg_reg_wen),
        .dbg_waddr  (dbg_reg_waddr),
        .dbg_wdata  (dbg_reg_wdata)
    );

    // ===========================================================
    // EX/MEM 前递信号（EX → ID forwarding）
    // 使用 EX/MEM 寄存器中的 ex_reg_wen/waddr/wdata
    // ===========================================================
    wire        fwd_ex_wen;
    wire [4:0]  fwd_ex_waddr;
    wire [31:0] fwd_ex_wdata;

    // ===========================================================
    // MEM/WB 前递信号（MEM → ID forwarding）
    // MEM 阶段是组合逻辑，fwd_wdata 是对齐后的最终写回值
    // ===========================================================
    wire        fwd_mem_wen;
    wire [4:0]  fwd_mem_waddr;
    wire [31:0] fwd_mem_wdata;  // MEM 阶段组合输出（对齐后）

    // ===========================================================
    // ID 阶段：指令译码
    // ===========================================================

    // ID 阶段输出信号
    wire [3:0]  id_alu_op;
    wire [31:0] id_alu_src1;
    wire [31:0] id_alu_src2;
    wire        id_mem_ren;
    wire        id_mem_wen;
    wire [2:0]  id_mem_funct3;
    wire [31:0] id_mem_wdata;
    wire        id_reg_wen;
    wire [4:0]  id_reg_waddr;
    wire        id_is_branch;
    wire [2:0]  id_branch_funct3;
    wire        id_is_jmp;
    wire [31:0] id_jmp_addr;
    wire [31:0] id_pc_out;
    wire [31:0] id_pc_plus4;
    wire        id_is_load;
    wire        id_inst_invalid;

    InstructionDecode u_id (
        .rst             (rst),
        .pc              (id_pc),
        .inst            (id_inst),
        .reg_rdata1      (id_reg_rdata1),
        .reg_rdata2      (id_reg_rdata2),
        .fwd_ex_wen      (fwd_ex_wen),
        .fwd_ex_waddr    (fwd_ex_waddr),
        .fwd_ex_wdata    (fwd_ex_wdata),
        .fwd_mem_wen     (fwd_mem_wen),
        .fwd_mem_waddr   (fwd_mem_waddr),
        .fwd_mem_wdata   (fwd_mem_wdata),
        .reg_raddr1      (id_reg_raddr1),
        .reg_raddr2      (id_reg_raddr2),
        .alu_op          (id_alu_op),
        .alu_src1        (id_alu_src1),
        .alu_src2        (id_alu_src2),
        .mem_ren         (id_mem_ren),
        .mem_wen         (id_mem_wen),
        .mem_funct3      (id_mem_funct3),
        .mem_wdata       (id_mem_wdata),
        .reg_wen         (id_reg_wen),
        .reg_waddr       (id_reg_waddr),
        .is_branch       (id_is_branch),
        .branch_funct3   (id_branch_funct3),
        .is_jmp          (id_is_jmp),
        .jmp_addr        (id_jmp_addr),
        .pc_out          (id_pc_out),
        .pc_plus4        (id_pc_plus4),
        .is_load         (id_is_load),
        .inst_invalid    (id_inst_invalid)
    );

    // ===========================================================
    // ID/EX 流水线寄存器
    // ===========================================================

    wire [31:0] ex_pc;
    wire [31:0] ex_pc_plus4;
    wire [3:0]  ex_alu_op;
    wire [31:0] ex_alu_src1;
    wire [31:0] ex_alu_src2;
    wire        ex_mem_ren;
    wire        ex_mem_wen;
    wire [2:0]  ex_mem_funct3;
    wire [31:0] ex_mem_wdata;
    wire        ex_reg_wen;
    wire [4:0]  ex_reg_waddr;
    wire        ex_is_branch;
    wire [2:0]  ex_branch_funct3;
    wire        ex_is_jmp_pipe;
    wire [31:0] ex_jmp_addr_pipe;
    wire        ex_is_load;

    IDEX u_id_ex (
        .clk              (clk),
        .rst              (rst),
        .flush            (idex_flush),
        .id_pc            (id_pc_out),
        .id_pc_plus4      (id_pc_plus4),
        .id_alu_op        (id_alu_op),
        .id_alu_src1      (id_alu_src1),
        .id_alu_src2      (id_alu_src2),
        .id_mem_ren       (id_mem_ren),
        .id_mem_wen       (id_mem_wen),
        .id_mem_funct3    (id_mem_funct3),
        .id_mem_wdata     (id_mem_wdata),
        .id_reg_wen       (id_reg_wen),
        .id_reg_waddr     (id_reg_waddr),
        .id_is_branch     (id_is_branch),
        .id_branch_funct3 (id_branch_funct3),
        .id_is_jmp        (id_is_jmp),
        .id_jmp_addr      (id_jmp_addr),
        .id_is_load       (id_is_load),
        .ex_pc            (ex_pc),
        .ex_pc_plus4      (ex_pc_plus4),
        .ex_alu_op        (ex_alu_op),
        .ex_alu_src1      (ex_alu_src1),
        .ex_alu_src2      (ex_alu_src2),
        .ex_mem_ren       (ex_mem_ren),
        .ex_mem_wen       (ex_mem_wen),
        .ex_mem_funct3    (ex_mem_funct3),
        .ex_mem_wdata     (ex_mem_wdata),
        .ex_reg_wen       (ex_reg_wen),
        .ex_reg_waddr     (ex_reg_waddr),
        .ex_is_branch     (ex_is_branch),
        .ex_branch_funct3 (ex_branch_funct3),
        .ex_is_jmp        (ex_is_jmp_pipe),
        .ex_jmp_addr      (ex_jmp_addr_pipe),
        .ex_is_load       (ex_is_load)
    );

    // ===========================================================
    // EX 阶段：ALU 计算 + 分支判断
    // ===========================================================

    wire [31:0] ex_alu_result;
    wire        ex_mem_ren_o;
    wire        ex_mem_wen_o;
    wire [2:0]  ex_mem_funct3_o;
    wire [31:0] ex_mem_wdata_o;
    wire [31:0] ex_mem_addr_o;
    wire        ex_reg_wen_o;
    wire [4:0]  ex_reg_waddr_o;
    wire [31:0] ex_reg_wdata_o;
    wire        ex_is_load_o;

    Execute u_ex (
        .rst             (rst),
        .pc              (ex_pc),
        .pc_plus4        (ex_pc_plus4),
        .alu_op          (ex_alu_op),
        .alu_src1        (ex_alu_src1),
        .alu_src2        (ex_alu_src2),
        .mem_ren         (ex_mem_ren),
        .mem_wen         (ex_mem_wen),
        .mem_funct3      (ex_mem_funct3),
        .mem_wdata       (ex_mem_wdata),
        .reg_wen         (ex_reg_wen),
        .reg_waddr       (ex_reg_waddr),
        .is_branch       (ex_is_branch),
        .branch_funct3   (ex_branch_funct3),
        .is_jmp          (ex_is_jmp_pipe),
        .jmp_addr        (ex_jmp_addr_pipe),
        .is_load         (ex_is_load),
        .alu_result      (ex_alu_result),
        .mem_ren_o       (ex_mem_ren_o),
        .mem_wen_o       (ex_mem_wen_o),
        .mem_funct3_o    (ex_mem_funct3_o),
        .mem_wdata_o     (ex_mem_wdata_o),
        .mem_addr_o      (ex_mem_addr_o),
        .reg_wen_o       (ex_reg_wen_o),
        .reg_waddr_o     (ex_reg_waddr_o),
        .reg_wdata_o     (ex_reg_wdata_o),
        .is_load_o       (ex_is_load_o),
        .jmp             (ex_jmp),
        .jmp_addr_o      (ex_jmp_addr)
    );

    // EX → ID 前递（EX/MEM 寄存器输入，即 EX 阶段组合输出）
    // 注意：EX 阶段是组合逻辑，直接用 EX 阶段组合输出做前递
    assign fwd_ex_wen   = ex_reg_wen_o;
    assign fwd_ex_waddr = ex_reg_waddr_o;
    assign fwd_ex_wdata = ex_reg_wdata_o;

    // ===========================================================
    // Hazard Unit：冒险检测
    // ===========================================================
    HazardUnit u_hazard (
        .ex_is_load     (ex_is_load),         // EX 阶段是否是 Load 指令
        .ex_reg_waddr   (ex_reg_waddr),        // EX 阶段目标寄存器
        .id_rs1         (id_reg_raddr1),       // ID 阶段 rs1
        .id_rs2         (id_reg_raddr2),       // ID 阶段 rs2
        .load_use_stall (load_use_stall),      // Load-use 冒险暂停信号
        .ex_jmp         (ex_jmp),              // EX 阶段实际跳转信号
        .branch_flush   (branch_flush)         // 分支/跳转冲刷信号
    );

    // ===========================================================
    // EX/MEM 流水线寄存器
    // ===========================================================

    wire [31:0] mem_alu_result;
    wire        mem_mem_ren;
    wire        mem_mem_wen;
    wire [2:0]  mem_mem_funct3;
    wire [31:0] mem_mem_wdata;
    wire [31:0] mem_mem_addr;
    wire        mem_reg_wen_pipe;
    wire [4:0]  mem_reg_waddr_pipe;
    wire [31:0] mem_reg_wdata_pipe;
    wire        mem_is_load;

    EXMEM u_ex_mem (
        .clk            (clk),
        .rst            (rst),
        .flush          (1'b0),               // EX/MEM 通常不需要单独 flush
        .ex_alu_result  (ex_alu_result),
        .ex_mem_ren     (ex_mem_ren_o),
        .ex_mem_wen     (ex_mem_wen_o),
        .ex_mem_funct3  (ex_mem_funct3_o),
        .ex_mem_wdata   (ex_mem_wdata_o),
        .ex_mem_addr    (ex_mem_addr_o),
        .ex_reg_wen     (ex_reg_wen_o),
        .ex_reg_waddr   (ex_reg_waddr_o),
        .ex_reg_wdata   (ex_reg_wdata_o),
        .ex_is_load     (ex_is_load_o),
        .mem_alu_result (mem_alu_result),
        .mem_mem_ren    (mem_mem_ren),
        .mem_mem_wen    (mem_mem_wen),
        .mem_mem_funct3 (mem_mem_funct3),
        .mem_mem_wdata  (mem_mem_wdata),
        .mem_mem_addr   (mem_mem_addr),
        .mem_reg_wen    (mem_reg_wen_pipe),
        .mem_reg_waddr  (mem_reg_waddr_pipe),
        .mem_reg_wdata  (mem_reg_wdata_pipe),
        .mem_is_load    (mem_is_load)
    );

    // ===========================================================
    // MEM 阶段：数据总线访问 + Load 数据对齐
    // ===========================================================

    wire        mem_wb_reg_wen;
    wire [4:0]  mem_wb_reg_waddr;
    wire [31:0] mem_wb_reg_wdata;
    wire [31:0] mem_fwd_wdata;    // MEM 阶段前递数据（对齐后）

    MemoryAccess u_mem (
        .alu_result   (mem_alu_result),
        .mem_ren      (mem_mem_ren),
        .mem_wen      (mem_mem_wen),
        .mem_funct3   (mem_mem_funct3),
        .mem_wdata    (mem_mem_wdata),
        .mem_addr     (mem_mem_addr),
        .reg_wen      (mem_reg_wen_pipe),
        .reg_waddr    (mem_reg_waddr_pipe),
        .reg_wdata    (mem_reg_wdata_pipe),
        .is_load      (mem_is_load),
        .dbus_addr    (dbus_addr),
        .dbus_ren     (dbus_ren),
        .dbus_wen     (dbus_wen),
        .dbus_be      (dbus_be),
        .dbus_wdata   (dbus_wdata),
        .dbus_rdata   (dbus_rdata),
        .wb_reg_wen   (mem_wb_reg_wen),
        .wb_reg_waddr (mem_wb_reg_waddr),
        .wb_reg_wdata (mem_wb_reg_wdata),
        .fwd_wdata    (mem_fwd_wdata)
    );

    // MEM → ID 前递：使用 MEM 阶段组合输出（对齐后的最终写回值）
    assign fwd_mem_wen   = mem_reg_wen_pipe;
    assign fwd_mem_waddr = mem_reg_waddr_pipe;
    assign fwd_mem_wdata = mem_fwd_wdata;

    // ===========================================================
    // MEM/WB 流水线寄存器
    // ===========================================================
    MEMWB u_mem_wb (
        .clk          (clk),
        .rst          (rst),
        .flush        (1'b0),                 // MEM/WB 通常不需要单独 flush
        .mem_reg_wen  (mem_wb_reg_wen),
        .mem_reg_waddr(mem_wb_reg_waddr),
        .mem_reg_wdata(mem_wb_reg_wdata),
        .wb_reg_wen   (wb_reg_wen),
        .wb_reg_waddr (wb_reg_waddr),
        .wb_reg_wdata (wb_reg_wdata)
    );

    // ===========================================================
    // WB 阶段：写回寄存器堆
    // wb_reg_wen/waddr/wdata 直接连到 RegFile 写端口（见上方 RegFile 实例化）
    // 此处无需独立的 WB 模块
    // ===========================================================

endmodule

`endif // CPU_CORE_SV
