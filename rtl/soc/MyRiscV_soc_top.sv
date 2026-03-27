`ifndef MYRISCV_SOC_TOP_SV
`define MYRISCV_SOC_TOP_SV

// ============================================================
//  MyRiscV SoC 顶层
//  连接：CpuCore、IRAM、DRAM、UART、JtagDTM、DebugModule、FlashCtrl
//
//  地址映射：
//    0x80000000 ~ 0x80003FFF  IRAM 16KB（FPGA BSRAM×8）
//    0x80004000 ~ 0x80005FFF  DRAM  8KB（FPGA BSRAM×4）
//    0x10000000 ~ 0x1000001F  UART
//    0x20000000 ~ 0x2012FFFF  Flash 76KB（片上 FLASH608K）
//    其他：返回 0
//
//  调试链路：
//    JtagDTM  ←DMI总线→  DebugModule  ←CPU调试接口→  CpuCore
//                              ↓SBA总线
//                           IRAM/DRAM 调试端口（地址路由）
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

// SBA 读数据在次周期有效（IRAM/DRAM 同步读，延迟 1 周期）
reg dm_sba_rdata_vld_r;
always @(posedge clk) dm_sba_rdata_vld_r <= dm_sba_ren;
assign dm_sba_rdata_vld = dm_sba_rdata_vld_r;

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
//  接收来自 JtagDTM 的 DMI 请求，控制 CpuCore 并通过 SBA 访问 IRAM/DRAM
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
    // System Bus Access（连接到 IRAM/DRAM 调试端口）
    .sba_addr       (dm_sba_addr),
    .sba_ren        (dm_sba_ren),
    .sba_wen        (dm_sba_wen),
    .sba_be         (dm_sba_be),
    .sba_wdata      (dm_sba_wdata),
    .sba_rdata      (dm_sba_rdata),
    .sba_rdata_vld  (dm_sba_rdata_vld)
);

// ---------------------------------------------------------
//  IRAM 例化（16KB，0x80000000 ~ 0x80003FFF）
// ---------------------------------------------------------
wire [31:0] iram_irdata;  // 指令端口输出
wire [31:0] iram_drdata;  // 数据端口输出
wire [31:0] iram_dbg_rdata;

// 地址译码
// IRAM：addr[31:14] == 18'h2_0000  (0x80000000 ~ 0x80003FFF)
wire sel_iram = (dbus_addr[31:14] == 18'h2_0000);

// UART 地址范围：0x10000000 ~ 0x1000001F
//   addr[31:12] == 20'h1_0000
wire sel_uart = (dbus_addr[31:12] == 20'h1_0000);

// DRAM：addr[31:13] == 19'h4_0002  (0x80004000 ~ 0x80005FFF)
wire sel_dram = (dbus_addr[31:13] == 19'h4_0002);

// Flash：0x20000000 ~ 0x2012FFFF（76KB 用户区，addr[31:17] == 15'h1000）
wire sel_flash = (dbus_addr[31:17] == 15'h1000);

// SBA 地址译码（DebugModule 系统总线访问路由）
wire sel_iram_dbg = (dm_sba_addr[31:14] == 18'h2_0000);
wire sel_dram_dbg = (dm_sba_addr[31:13] == 19'h4_0002);

IRAM u_iram (
    .clk        (clk),
    // 指令端口（来自 CPU IF，始终连接）
    .iaddr      (iram_addr),
    .idata      (iram_irdata),  // 指令端口输出
    // 数据端口（来自 CPU MEM）
    .daddr      (dbus_addr),
    .dren       (dbus_ren  & sel_iram),
    .dwen       (dbus_wen  & sel_iram),
    .dbe        (dbus_be),
    .dwdata     (dbus_wdata),
    .drdata     (iram_drdata),  // 数据端口输出
    // 调试端口（来自 DebugModule SBA）
    .dbg_addr   (dm_sba_addr),
    .dbg_ren    (dm_sba_ren  & sel_iram_dbg),
    .dbg_wen    (dm_sba_wen  & sel_iram_dbg),
    .dbg_be     (dm_sba_be),
    .dbg_wdata  (dm_sba_wdata),
    .dbg_rdata  (iram_dbg_rdata)
);

// ---------------------------------------------------------
//  DRAM 例化（8KB，0x80004000 ~ 0x80005FFF）
// ---------------------------------------------------------
wire [31:0] dram_drdata;
wire [31:0] dram_dbg_rdata;

DRAM u_dram (
    .clk        (clk),
    // 数据端口（来自 CPU MEM）
    .daddr      (dbus_addr),
    .dren       (dbus_ren  & sel_dram),
    .dwen       (dbus_wen  & sel_dram),
    .dbe        (dbus_be),
    .dwdata     (dbus_wdata),
    .drdata     (dram_drdata),
    // 调试端口（来自 DebugModule SBA）
    .dbg_addr   (dm_sba_addr),
    .dbg_ren    (dm_sba_ren  & sel_dram_dbg),
    .dbg_wen    (dm_sba_wen  & sel_dram_dbg),
    .dbg_be     (dm_sba_be),
    .dbg_wdata  (dm_sba_wdata),
    .dbg_rdata  (dram_dbg_rdata)
);

// DebugModule SBA 读数据回路（按地址路由到 IRAM 或 DRAM）
assign dm_sba_rdata = sel_iram_dbg ? iram_dbg_rdata :
                      sel_dram_dbg ? dram_dbg_rdata :
                                     32'h0000_0000;

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
//  FlashCtrl 例化（76KB 片上 Flash，0x20000000）
// ---------------------------------------------------------
wire [31:0] flash_rdata;
wire        flash_rdata_vld;

// Flash 指令读接口（XIP：CPU 取指）
wire [31:0] flash_irdata;
wire        flash_irdata_vld;

// Flash 取指译码：iram_addr[31:17] == 15'h1000 (0x20000000 ~ 0x2012FFFF)
wire sel_flash_if = (iram_addr[31:17] == 15'h1000);

FlashCtrl u_flash_ctrl (
    .clk           (clk),
    .rst           (rst),
    // 指令端口（CPU 取指）
    .iaddr         (iram_addr),
    .iren          (sel_flash_if),
    .irdata        (flash_irdata),
    .irdata_vld    (flash_irdata_vld),
    // 数据端口（CPU 读写）
    .cpu_addr      (dbus_addr),
    .cpu_ren       (dbus_ren & sel_flash),
    .cpu_rdata     (flash_rdata),
    .cpu_rdata_vld (flash_rdata_vld)
);

// IRAM/Flash 数据 MUX（指令读数据）
// Flash 访问时选通 flash_irdata，否则选通 IRAM 指令端口
assign iram_rdata = sel_flash_if ? flash_irdata : iram_irdata;

// ---------------------------------------------------------
//  数据总线读数据 MUX（组合逻辑）
//  根据地址选择 UART、IRAM、DRAM 或 Flash 的读数据
// ---------------------------------------------------------
assign dbus_rdata = sel_uart  ? uart_rdata  :
                    sel_iram  ? iram_drdata :
                    sel_dram  ? dram_drdata :
                    sel_flash ? flash_rdata :
                                32'h0000_0000;

// ---------------------------------------------------------
//  LED 调试指示（低有效，板载 6 个 LED）
//  led[5]：CPU halted 状态指示
//  其余：保留（常亮，即 0 = 亮）
// ---------------------------------------------------------
assign led = ~{dbg_halted, 5'b00000};

endmodule

`endif // MYRISCV_SOC_TOP_SV
