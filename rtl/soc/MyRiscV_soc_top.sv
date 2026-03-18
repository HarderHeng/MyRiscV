`ifndef MYRISCV_SOC_TOP_SV
`define MYRISCV_SOC_TOP_SV

// ============================================================
//  MyRiscV SoC 顶层
//  连接：CpuCore、SimRAM、UART、JtagDTM、DebugModule
//
//  地址映射：
//    0x80000000 ~ 0x80003FFF  IRAM（16KB，在 SimRAM 低 16KB）
//    0x80004000 ~ 0x80007FFF  DRAM（16KB，在 SimRAM 高 16KB）
//    0x10000000 ~ 0x1000001F  UART
//    其他：返回 0
//
//  调试链路：
//    JtagDTM  ←DMI总线→  DebugModule  ←CPU调试接口→  CpuCore
//                              ↓SBA总线
//                           SimRAM 调试端口
// ============================================================
module MyRiscV_soc_top (
    input  wire        clk,
    input  wire        rst_n,     // 低有效复位（来自按键）
    output wire        uart_tx,
    input  wire        uart_rx,
    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo,
    input  wire        jtag_trst_n,
    output wire [5:0]  led
);

// ---------------------------------------------------------
//  复位信号（高有效，内部使用）
// ---------------------------------------------------------
wire rst = ~rst_n;

// ---------------------------------------------------------
//  CPU 核心接口信号
// ---------------------------------------------------------
// 指令总线
wire [31:0] iram_addr;   // CPU 取指地址
wire [31:0] iram_rdata;  // 指令数据

// 数据总线
wire [31:0] dbus_addr;
wire        dbus_ren;
wire        dbus_wen;
wire [3:0]  dbus_be;
wire [31:0] dbus_wdata;
wire [31:0] dbus_rdata;

// ---------------------------------------------------------
//  调试接口信号（CpuCore ↔ DebugModule）
// ---------------------------------------------------------
wire        dbg_halt_req;
wire        dbg_halted;
wire        dbg_resume_req;
wire [4:0]  dbg_reg_raddr;
wire [31:0] dbg_reg_rdata;
wire        dbg_reg_wen;
wire [4:0]  dbg_reg_waddr;
wire [31:0] dbg_reg_wdata;
wire [31:0] dbg_pc;

// ---------------------------------------------------------
//  DMI 总线信号（JtagDTM ↔ DebugModule）
// ---------------------------------------------------------
wire [6:0]  dmi_addr;
wire [31:0] dmi_wdata;
wire [1:0]  dmi_op;
wire        dmi_req;
wire [31:0] dmi_rdata;
wire [1:0]  dmi_resp;
wire        dmi_ack;

// ---------------------------------------------------------
//  系统总线访问（SBA）信号（DebugModule ↔ SimRAM 调试端口）
// ---------------------------------------------------------
wire [31:0] dm_sba_addr;
wire        dm_sba_ren;
wire        dm_sba_wen;
wire [3:0]  dm_sba_be;
wire [31:0] dm_sba_wdata;
wire [31:0] dm_sba_rdata;
wire        dm_sba_rdata_vld;

// SBA 读数据在同周期有效（SimRAM 组合读），始终有效
assign dm_sba_rdata_vld = dm_sba_ren;

// ---------------------------------------------------------
//  CPU 核心例化
// ---------------------------------------------------------
CpuCore u_cpu_core (
    .clk            (clk),
    .rst            (rst),
    // 指令存储器接口
    .iram_addr      (iram_addr),
    .iram_rdata     (iram_rdata),
    // 数据总线接口
    .dbus_addr      (dbus_addr),
    .dbus_ren       (dbus_ren),
    .dbus_wen       (dbus_wen),
    .dbus_be        (dbus_be),
    .dbus_wdata     (dbus_wdata),
    .dbus_rdata     (dbus_rdata),
    // 调试接口
    .dbg_halt_req   (dbg_halt_req),
    .dbg_halted     (dbg_halted),
    .dbg_resume_req (dbg_resume_req),
    .dbg_reg_raddr  (dbg_reg_raddr),
    .dbg_reg_rdata  (dbg_reg_rdata),
    .dbg_reg_wen    (dbg_reg_wen),
    .dbg_reg_waddr  (dbg_reg_waddr),
    .dbg_reg_wdata  (dbg_reg_wdata),
    .dbg_pc         (dbg_pc)
);

// ---------------------------------------------------------
//  JtagDTM（Debug Transport Module）例化
//  通过 DMI 总线连接到 DebugModule
// ---------------------------------------------------------
JtagDTM u_jtag_dtm (
    // JTAG 物理引脚
    .tck        (jtag_tck),
    .tms        (jtag_tms),
    .tdi        (jtag_tdi),
    .tdo        (jtag_tdo),
    .trst_n     (jtag_trst_n),
    // 系统时钟（用于跨域同步）
    .clk        (clk),
    .rst        (rst),
    // DMI 总线（系统时钟域，连接到 DebugModule）
    .dmi_addr   (dmi_addr),
    .dmi_wdata  (dmi_wdata),
    .dmi_op     (dmi_op),
    .dmi_req    (dmi_req),
    .dmi_rdata  (dmi_rdata),
    .dmi_resp   (dmi_resp),
    .dmi_ack    (dmi_ack)
);

// ---------------------------------------------------------
//  DebugModule 例化
//  接收来自 JtagDTM 的 DMI 请求，控制 CpuCore 并通过 SBA 访问 SimRAM
// ---------------------------------------------------------
DebugModule u_debug_module (
    .clk            (clk),
    .rst            (rst),
    // DTM 接口（来自 JtagDTM）
    .dmi_addr       (dmi_addr),
    .dmi_wdata      (dmi_wdata),
    .dmi_op         (dmi_op),
    .dmi_req        (dmi_req),
    .dmi_rdata      (dmi_rdata),
    .dmi_resp       (dmi_resp),
    .dmi_ack        (dmi_ack),
    // CPU 调试接口（连接到 CpuCore）
    .cpu_halt_req   (dbg_halt_req),
    .cpu_halted     (dbg_halted),
    .cpu_resume_req (dbg_resume_req),
    .cpu_reset_req  (/* 未连接，ndmreset 功能暂不使用 */),
    // CPU 寄存器访问（Abstract Command）
    .dbg_reg_raddr  (dbg_reg_raddr),
    .dbg_reg_rdata  (dbg_reg_rdata),
    .dbg_reg_wen    (dbg_reg_wen),
    .dbg_reg_waddr  (dbg_reg_waddr),
    .dbg_reg_wdata  (dbg_reg_wdata),
    .dbg_pc         (/* 输出，DebugModule 内部透传 cpu_pc 的只读端口，不需要连接 */),
    .cpu_pc         (dbg_pc),
    // System Bus Access（连接到 SimRAM 调试端口）
    .sba_addr       (dm_sba_addr),
    .sba_ren        (dm_sba_ren),
    .sba_wen        (dm_sba_wen),
    .sba_be         (dm_sba_be),
    .sba_wdata      (dm_sba_wdata),
    .sba_rdata      (dm_sba_rdata),
    .sba_rdata_vld  (dm_sba_rdata_vld)
);

// ---------------------------------------------------------
//  SimRAM 例化（仿真用 IRAM+DRAM 合一）
// ---------------------------------------------------------
wire [31:0] sim_ram_drdata;
wire [31:0] sim_ram_dbg_rdata;

// 地址译码（组合逻辑）
// SimRAM 地址范围：0x80000000 ~ 0x80007FFF
//   addr[31:15] == 17'h1_0000
wire sel_sim_ram = (dbus_addr[31:15] == 17'h1_0000);

// UART 地址范围：0x10000000 ~ 0x1000001F
//   addr[31:12] == 20'h1_0000
wire sel_uart    = (dbus_addr[31:12] == 20'h1_0000);

SimRAM u_sim_ram (
    .clk        (clk),
    // 指令端口（来自 CPU IF）
    .iaddr      (iram_addr),
    .idata      (iram_rdata),
    // 数据端口（来自 CPU MEM 阶段）
    .daddr      (dbus_addr),
    .dren       (dbus_ren  & sel_sim_ram),
    .dwen       (dbus_wen  & sel_sim_ram),
    .dbe        (dbus_be),
    .dwdata     (dbus_wdata),
    .drdata     (sim_ram_drdata),
    // 调试端口（来自 DebugModule SBA）
    .dbg_addr   (dm_sba_addr),
    .dbg_ren    (dm_sba_ren),
    .dbg_wen    (dm_sba_wen),
    .dbg_be     (dm_sba_be),
    .dbg_wdata  (dm_sba_wdata),
    .dbg_rdata  (sim_ram_dbg_rdata)
);

// DebugModule SBA 读数据回路（仅 SimRAM 范围）
assign dm_sba_rdata = sim_ram_dbg_rdata;

// ---------------------------------------------------------
//  UART 例化
// ---------------------------------------------------------
wire [31:0] uart_rdata;

UART u_uart (
    .clk        (clk),
    .rst        (rst),
    // 总线接口：地址取低 5 位（对应 UART 内部寄存器偏移）
    .addr       (dbus_addr[4:0]),
    .wen        (dbus_wen & sel_uart),
    .ren        (dbus_ren & sel_uart),
    .wdata      (dbus_wdata),
    .rdata      (uart_rdata),
    // IO
    .uart_tx    (uart_tx),
    .uart_rx    (uart_rx)
);

// ---------------------------------------------------------
//  数据总线读数据 MUX（组合逻辑）
//  根据地址选择 SimRAM 或 UART 的读数据
// ---------------------------------------------------------
assign dbus_rdata = sel_uart    ? uart_rdata     :
                    sel_sim_ram ? sim_ram_drdata  :
                                  32'h0000_0000;

// ---------------------------------------------------------
//  LED 调试指示（低有效，板载 6 个 LED）
//  led[5]：CPU halted 状态指示
//  其余：保留（常亮，即 0 = 亮）
// ---------------------------------------------------------
assign led = ~{dbg_halted, 5'b00000};

endmodule

`endif // MYRISCV_SOC_TOP_SV
