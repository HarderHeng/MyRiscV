`ifndef MYRISCV_AHB_SOC_SV
`define MYRISCV_AHB_SOC_SV

// ============================================================
//  MyRiscV SoC Top - AHB-Lite 版本
//
//  特性:
//    - 使用 AHB-Lite 总线连接所有组件
//    - 统一的地址解码和从设备选择
//    - 支持 I-Cache 和 D-Cache（可选）
//
//  地址映射:
//    0x1000_xxxx  UART (0x10000000)
//    0x2000_xxxx  Flash XIP (0x20000000 - 0x2012FFFF)
//    0x8000_xxxx  SRAM
//      0x8000_0000 - 0x8000_3FFF  IRAM (16KB)
//      0x8000_4000 - 0x8000_5FFF  DRAM (8KB)
// ============================================================
module MyRiscV_ahb_soc (
    input  wire        clk,
    input  wire        rst_n,

    output wire        uart_tx,
    input  wire        uart_rx,

    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo,
    input  wire        jtag_trst_n,

    output wire [31:0] gpio_out,
    input  wire [31:0] gpio_in,

    output wire [5:0]  led
);

    // ============================================================
    //  复位信号
    // ============================================================
    wire rst = ~rst_n;

    // ============================================================
    //  AHB-Lite 信号
    // ============================================================

    // CPU AHB 主设备接口
    wire [31:0] haddr;
    wire        hsel;
    wire        hready_in;
    wire [1:0]  htrans;
    wire        hwrite;
    wire [2:0]  hsize;
    wire [3:0]  hstrb;
    wire [31:0] hwdata;
    wire [31:0] hrdata;
    wire        hreadyout;
    wire        hresp;

    // 从设备信号
    wire [31:0] iram_haddr;
    wire        iram_hsel;
    wire        iram_hready;
    wire [1:0]  iram_htrans;
    wire        iram_hwrite;
    wire [2:0]  iram_hsize;
    wire [3:0]  iram_hstrb;
    wire [31:0] iram_hwdata;
    wire [31:0] iram_hrdata;
    wire        iram_hreadyout;
    wire        iram_hresp;

    wire [31:0] dram_haddr;
    wire        dram_hsel;
    wire        dram_hready;
    wire [1:0]  dram_htrans;
    wire        dram_hwrite;
    wire [2:0]  dram_hsize;
    wire [3:0]  dram_hstrb;
    wire [31:0] dram_hwdata;
    wire [31:0] dram_hrdata;
    wire        dram_hreadyout;
    wire        dram_hresp;

    wire [31:0] flash_haddr;
    wire        flash_hsel;
    wire        flash_hready;
    wire [1:0]  flash_htrans;
    wire        flash_hwrite;
    wire [2:0]  flash_hsize;
    wire [3:0]  flash_hstrb;
    wire [31:0] flash_hwdata;
    wire [31:0] flash_hrdata;
    wire        flash_hreadyout;
    wire        flash_hresp;

    wire [31:0] periph_haddr;
    wire        periph_hsel;
    wire        periph_hready;
    wire [1:0]  periph_htrans;
    wire        periph_hwrite;
    wire [2:0]  periph_hsize;
    wire [3:0]  periph_hstrb;
    wire [31:0] periph_hwdata;
    wire [31:0] periph_hrdata;
    wire        periph_hreadyout;
    wire        periph_hresp;

    // ============================================================
    //  CPU AHB 桥接器
    // ============================================================
    CPU_AHB_Bridge u_cpu_bridge (
        .clk        (clk),
        .rst        (rst),

        // CPU 原始接口
        .iram_addr  (iram_addr),
        .iram_req   (sel_flash_if),
        .iram_rdata (iram_rdata),
        .iram_ready (),

        .dbus_addr  (dbus_addr),
        .dbus_ren   (dbus_ren),
        .dbus_wen   (dbus_wen),
        .dbus_be    (dbus_be),
        .dbus_wdata (dbus_wdata),
        .dbus_rdata (dbus_rdata),
        .dbus_ready (),

        // AHB 主设备接口
        .haddr      (haddr),
        .hsel       (hsel),
        .hready_in  (hready_in),
        .htrans     (htrans),
        .hwrite     (hwrite),
        .hsize      (hsize),
        .hstrb      (hstrb),
        .hwdata     (hwdata),
        .hrdata     (hrdata),
        .hreadyout  (hreadyout),
        .hresp      (hresp)
    );

    // ============================================================
    //  AHB-Lite 总线
    // ============================================================
    AHB_Lite_Bus u_bus (
        .clk        (clk),
        .rst        (rst),

        // 主设备接口
        .haddr_m    (haddr),
        .hsel_m     (hsel),
        .hready_m   (hready_in),
        .htrans_m   (htrans),
        .hwrite_m   (hwrite),
        .hsize_m    (hsize),
        .hstrb_m    (hstrb),
        .hwdata_m   (hwdata),
        .hrdata_m   (hrdata),
        .hreadyout_m (hreadyout),
        .hresp_m    (hresp),

        // IRAM 从设备
        .s0_addr    (iram_haddr),
        .s0_ren     (iram_hsel & ~iram_hwrite),
        .s0_wen     (iram_hsel & iram_hwrite),
        .s0_be      (iram_hstrb),
        .s0_wdata   (iram_hwdata),
        .s0_rdata   (iram_hrdata),
        .s0_ready   (iram_hreadyout),

        // DRAM 从设备
        .s1_addr    (dram_haddr),
        .s1_ren     (dram_hsel & ~dram_hwrite),
        .s1_wen     (dram_hsel & dram_hwrite),
        .s1_be      (dram_hstrb),
        .s1_wdata   (dram_hwdata),
        .s1_rdata   (dram_hrdata),
        .s1_ready   (dram_hreadyout),

        // Flash 从设备
        .s2_addr    (flash_haddr),
        .s2_ren     (flash_hsel & ~flash_hwrite),
        .s2_wen     (flash_hsel & flash_hwrite),
        .s2_be      (flash_hstrb),
        .s2_wdata   (flash_hwdata),
        .s2_rdata   (flash_hrdata),
        .s2_ready   (flash_hreadyout),

        // 外设从设备
        .s3_addr    (periph_haddr),
        .s3_ren     (periph_hsel & ~periph_hwrite),
        .s3_wen     (periph_hsel & periph_hwrite),
        .s3_be      (periph_hstrb),
        .s3_wdata   (periph_hwdata),
        .s3_rdata   (periph_hrdata),
        .s3_ready   (periph_hreadyout)
    );

    // ============================================================
    //  IRAM (16KB) - 带 AHB 从设备接口
    // ============================================================
    wire [31:0] iram_addr;
    wire [31:0] iram_rdata_int;

    AHB_Lite_RAM u_iram_ahb (
        .hclk       (clk),
        .hresetn    (~rst),

        .haddr      (iram_haddr),
        .hsel       (iram_hsel),
        .hready_in  (1'b1),
        .htrans     (2'b10),
        .hwrite     (iram_hwrite),
        .hsize      (3'b010),
        .hstrb      (iram_hstrb),
        .hwdata     (iram_hwdata),
        .hrdata     (iram_hrdata),
        .hreadyout  (iram_hreadyout),
        .hresp      (iram_hresp),

        .ram_addr   (iram_addr),
        .ram_ren    (),
        .ram_wen    (),
        .ram_be     (),
        .ram_wdata  (),
        .ram_rdata  (iram_rdata_int),
        .ram_ready  (1'b1)
    );

    // 直接连接到 IRAM 的原始端口用于指令
    IRAM u_iram (
        .clk    (clk),

        .iaddr  (iram_addr),
        .idata  (iram_rdata),

        .daddr  (iram_haddr),
        .dren   (iram_hsel & ~iram_hwrite),
        .dwen   (iram_hsel & iram_hwrite),
        .dbe    (iram_hstrb),
        .dwdata (iram_hwdata),
        .drdata (),

        .dbg_addr  (32'h0),
        .dbg_ren   (1'b0),
        .dbg_wen   (1'b0),
        .dbg_be    (4'h0),
        .dbg_wdata (32'h0),
        .dbg_rdata ()
    );

    // ============================================================
    //  DRAM (8KB) - 带 AHB 从设备接口
    // ============================================================
    wire [31:0] dram_addr;
    wire [31:0] dram_rdata_int;

    AHB_Lite_RAM u_dram_ahb (
        .hclk       (clk),
        .hresetn    (~rst),

        .haddr      (dram_haddr),
        .hsel       (dram_hsel),
        .hready_in  (1'b1),
        .htrans     (2'b10),
        .hwrite     (dram_hwrite),
        .hsize      (3'b010),
        .hstrb      (dram_hstrb),
        .hwdata     (dram_hwdata),
        .hrdata     (dram_hrdata),
        .hreadyout  (dram_hreadyout),
        .hresp      (dram_hresp),

        .ram_addr   (dram_addr),
        .ram_ren    (),
        .ram_wen    (),
        .ram_be     (),
        .ram_wdata  (),
        .ram_rdata  (dram_rdata_int),
        .ram_ready  (1'b1)
    );

    DRAM u_dram (
        .clk    (clk),

        .daddr  (dram_addr),
        .dren   (dram_hsel & ~dram_hwrite),
        .dwen   (dram_hsel & dram_hwrite),
        .dbe    (dram_hstrb),
        .dwdata (dram_hwdata),
        .drdata (dram_rdata_int),

        .dbg_addr  (32'h0),
        .dbg_ren   (1'b0),
        .dbg_wen   (1'b0),
        .dbg_be    (4'h0),
        .dbg_wdata (32'h0),
        .dbg_rdata ()
    );

    // ============================================================
    //  FlashCtrl (76KB)
    // ============================================================
    wire [31:0] flash_irdata;
    wire [31:0] flash_rdata;

    FlashCtrl u_flash (
        .clk         (clk),
        .rst         (rst),

        .cpu_addr    (flash_haddr),
        .cpu_ren     (flash_hsel & ~flash_hwrite),
        .cpu_rdata   (flash_hrdata),
        .cpu_rdata_vld(),

        .iaddr       (iram_addr),
        .iren        (sel_flash_if),
        .irdata      (flash_irdata),
        .irdata_vld  ()
    );

    // ============================================================
    //  UART
    // ============================================================
    wire [31:0] uart_rdata;

    UART u_uart (
        .clk    (clk),
        .rst    (rst),

        .addr   (periph_haddr[4:2]),
        .wen    (periph_hsel & periph_hwrite),
        .ren    (periph_hsel & ~periph_hwrite),
        .wdata  (periph_hwdata),
        .rdata  (periph_hrdata),

        .uart_tx (uart_tx),
        .uart_rx (uart_rx)
    );

    // ============================================================
    //  GPIO (简化)
    // ============================================================
    assign gpio_out = 32'h0;

    // ============================================================
    //  IRAM/Flash 指令 MUX
    // ============================================================
    assign iram_rdata = sel_flash_if ? flash_irdata : iram_rdata_int;

    // ============================================================
    //  地址译码（保持与原始设计兼容）
    // ============================================================
    wire sel_flash_if = (iram_addr[31:17] == 15'h1000);

    // ============================================================
    //  CPU Core (原始接口)
    // ============================================================
    wire [31:0] dbus_addr;
    wire        dbus_ren;
    wire        dbus_wen;
    wire [3:0]  dbus_be;
    wire [31:0] dbus_wdata;
    wire [31:0] dbus_rdata;

    CpuCore u_cpu (
        .clk         (clk),
        .rst         (rst),

        .iram_addr   (iram_addr),
        .iram_rdata  (iram_rdata),

        .dbus_addr   (dbus_addr),
        .dbus_ren    (dbus_ren),
        .dbus_wen    (dbus_wen),
        .dbus_be     (dbus_be),
        .dbus_wdata  (dbus_wdata),
        .dbus_rdata  (dbus_rdata),

        .dbg_halt_req   (1'b0),
        .dbg_halted     (),
        .dbg_resume_req (1'b0),
        .dbg_reg_raddr  (5'b0),
        .dbg_reg_rdata  (),
        .dbg_reg_wen    (1'b0),
        .dbg_reg_waddr  (5'b0),
        .dbg_reg_wdata  (32'b0),
        .dbg_pc         ()
    );

    // ============================================================
    //  Debug Module (简化)
    // ============================================================
    assign jtag_tdo = 1'b0;

    // ============================================================
    //  LED
    // ============================================================
    assign led = 6'b111111;

endmodule

`endif // MYRISCV_AHB_SOC_SV
