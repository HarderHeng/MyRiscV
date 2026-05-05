`ifndef MYRISCV_SOC_TOP_SV
`define MYRISCV_SOC_TOP_SV
`timescale 1ns/1ps

// ============================================================
//  MyRiscV SoC Top - 简化版（恢复到原始设计）
//
//  地址映射:
//    0x1000_xxxx  UART (0x10000000)
//    0x2000_xxxx  Flash XIP (0x20000000 - 0x2012FFFF)
//    0x8000_xxxx  SRAM
//      0x8000_0000 - 0x8000_3FFF  IRAM (16KB)
//      0x8000_4000 - 0x8000_5FFF  DRAM (8KB)
// ============================================================
module MyRiscV_soc_top (
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
    //  CPU 信号
    // ============================================================
    wire [31:0] iram_addr;
    wire [31:0] iram_rdata;
    wire [31:0] dbus_addr;
    wire        dbus_ren;
    wire        dbus_wen;
    wire [3:0]  dbus_be;
    wire [31:0] dbus_wdata;
    wire [31:0] dbus_rdata;

    // ============================================================
    //  Debug 信号
    // ============================================================
    wire        dbg_halt_req;
    wire        dbg_halted;
    wire        dbg_resume_req;
    wire [4:0]  dbg_reg_raddr;
    wire [31:0] dbg_reg_rdata;
    wire        dbg_reg_wen;
    wire [4:0]  dbg_reg_waddr;
    wire [31:0] dbg_reg_wdata;
    wire [31:0] dbg_pc;

    // ============================================================
    //  地址译码
    // ============================================================

    // IRAM: 0x80000000 - 0x80003FFF (addr[31:14] == 18'h2_0000)
    wire sel_iram = (dbus_addr[31:14] == 18'h2_0000);

    // DRAM: 0x80004000 - 0x80005FFF (addr[31:13] == 19'h4_0002)
    wire sel_dram = (dbus_addr[31:13] == 19'h4_0002);

    // UART: 0x10000000 - 0x1000001F (addr[31:12] == 20'h1_0000)
    wire sel_uart = (dbus_addr[31:12] == 20'h1_0000);

    // Flash: 0x20000000 - 0x2012FFFF (addr[31:17] == 15'h1000)
    wire sel_flash = (dbus_addr[31:17] == 15'h1000);

    // Flash指令取指: iram_addr[31:17] == 15'h1000
    wire sel_flash_if = (iram_addr[31:17] == 15'h1000);

    // ============================================================
    //  CPU Core
    // ============================================================
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
    //  IRAM (16KB)
    // ============================================================
    wire [31:0] iram_irdata;
    wire [31:0] iram_drdata;

    IRAM u_iram (
        .clk    (clk),

        .iaddr  (iram_addr),
        .idata  (iram_irdata),

        .daddr  (dbus_addr),
        .dren   (dbus_ren & sel_iram),
        .dwen   (dbus_wen & sel_iram),
        .dbe    (dbus_be),
        .dwdata (dbus_wdata),
        .drdata (iram_drdata),

        .dbg_addr  (32'h0),
        .dbg_ren   (1'b0),
        .dbg_wen   (1'b0),
        .dbg_be    (4'h0),
        .dbg_wdata (32'h0),
        .dbg_rdata ()
    );

    // ============================================================
    //  DRAM (8KB)
    // ============================================================
    wire [31:0] dram_drdata;

    DRAM u_dram (
        .clk    (clk),

        .daddr  (dbus_addr),
        .dren   (dbus_ren & sel_dram),
        .dwen   (dbus_wen & sel_dram),
        .dbe    (dbus_be),
        .dwdata (dbus_wdata),
        .drdata (dram_drdata),

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
    wire        flash_irdata_vld;
    wire [31:0] flash_rdata;
    wire        flash_rdata_vld;

    FlashCtrl u_flash (
        .clk         (clk),
        .rst         (rst),

        .cpu_addr    (dbus_addr),
        .cpu_ren     (dbus_ren & sel_flash),
        .cpu_rdata   (flash_rdata),
        .cpu_rdata_vld(flash_rdata_vld),

        .iaddr       (iram_addr),
        .iren        (sel_flash_if),
        .irdata      (flash_irdata),
        .irdata_vld  (flash_irdata_vld)
    );

    // ============================================================
    //  IRAM/Flash 指令 MUX
    // ============================================================
    assign iram_rdata = sel_flash_if ? flash_irdata : iram_irdata;

    // ============================================================
    //  UART
    // ============================================================
    wire [31:0] uart_rdata;

    UART u_uart (
        .clk    (clk),
        .rst    (rst),

        .addr   (dbus_addr[4:2]),
        .wen    (dbus_wen & sel_uart),
        .ren    (dbus_ren & sel_uart),
        .wdata  (dbus_wdata),
        .rdata  (uart_rdata),

        .uart_tx (uart_tx),
        .uart_rx (uart_rx)
    );

    // ============================================================
    //  GPIO (简化，暂不连接)
    // ============================================================
    assign gpio_out = 32'h0;

    // ============================================================
    //  数据总线 MUX
    // ============================================================
    assign dbus_rdata = sel_uart  ? uart_rdata :
                         sel_iram  ? iram_drdata :
                         sel_dram  ? dram_drdata :
                         sel_flash ? flash_rdata :
                                     32'h0;

    // ============================================================
    //  Debug Module (简化，不连接)
    // ============================================================
    assign jtag_tdo = 1'b0;

    // ============================================================
    //  LED
    // ============================================================
    assign led = 6'b111111;  // All on

endmodule

`endif // MYRISCV_SOC_TOP_SV