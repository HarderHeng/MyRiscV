// MyRiscV SoC - Top Level Module
// 5-Stage Pipeline RISC-V Processor for TangNano-9K

module top (
    input  wire        clk,        // 27MHz clock
    input  wire        rst_n,      // Active-low reset
    // UART
    input  wire        uart_rx,
    output wire        uart_tx,
    // LEDs
    output wire [5:0]  led
);

    // Internal reset
    wire rst;
    assign rst = ~rst_n;

    // ========== CPU Signals ==========
    wire [31:0] cpu_i_addr;
    wire [31:0] cpu_i_rdata;
    wire        cpu_i_ready;

    wire [31:0] cpu_d_addr;
    wire        cpu_d_req;
    wire        cpu_d_we;
    wire [3:0]  cpu_d_be;
    wire [31:0] cpu_d_wdata;
    wire [31:0] cpu_d_rdata;
    wire        cpu_d_ready;

    // ========== Bus Signals ==========
    // IRAM (I-port)
    wire [31:0] iram_i_addr;
    wire        iram_i_req;
    wire [31:0] iram_i_rdata;
    wire        iram_i_ready;

    // IRAM (D-port)
    wire [31:0] iram_d_addr;
    wire        iram_d_req;
    wire        iram_d_we;
    wire [3:0]  iram_d_be;
    wire [31:0] iram_d_wdata;
    wire [31:0] iram_d_rdata;
    wire        iram_d_ready;

    // DRAM
    wire [31:0] dram_addr;
    wire        dram_req;
    wire        dram_we;
    wire [3:0]  dram_be;
    wire [31:0] dram_wdata;
    wire [31:0] dram_rdata;
    wire        dram_ready;

    // Flash
    wire [31:0] flash_addr;
    wire        flash_req;
    wire [31:0] flash_rdata;
    wire        flash_ready;

    // UART
    wire [31:0] uart_addr;
    wire        uart_req;
    wire        uart_we;
    wire [3:0]  uart_be;
    wire [31:0] uart_wdata;
    wire [31:0] uart_rdata;
    wire        uart_ready;

    // ========== CPU Core ==========
    cpu u_cpu (
        .clk        (clk),
        .rst        (rst),
        // Instruction fetch
        .i_addr     (cpu_i_addr),
        .i_rdata    (cpu_i_rdata),
        .i_ready    (cpu_i_ready),
        // Data memory
        .d_addr     (cpu_d_addr),
        .d_req      (cpu_d_req),
        .d_we       (cpu_d_we),
        .d_be       (cpu_d_be),
        .d_wdata    (cpu_d_wdata),
        .d_rdata    (cpu_d_rdata),
        .d_ready    (cpu_d_ready)
    );

    // ========== Bus Matrix ==========
    bus u_bus (
        .clk        (clk),
        .rst        (rst),
        // CPU I-BUS
        .i_addr     (cpu_i_addr),
        .i_req      (1'b1),
        .i_rdata    (cpu_i_rdata),
        .i_ready    (cpu_i_ready),
        // CPU D-BUS
        .d_addr     (cpu_d_addr),
        .d_req      (cpu_d_req),
        .d_we       (cpu_d_we),
        .d_be       (cpu_d_be),
        .d_wdata    (cpu_d_wdata),
        .d_rdata    (cpu_d_rdata),
        .d_ready    (cpu_d_ready),
        // IRAM I-port
        .iram_i_addr(iram_i_addr),
        .iram_i_req (iram_i_req),
        .iram_i_rdata(iram_i_rdata),
        .iram_i_ready(iram_i_ready),
        // IRAM D-port
        .iram_d_addr(iram_d_addr),
        .iram_d_req (iram_d_req),
        .iram_d_we  (iram_d_we),
        .iram_d_be  (iram_d_be),
        .iram_d_wdata(iram_d_wdata),
        .iram_d_rdata(iram_d_rdata),
        .iram_d_ready(iram_d_ready),
        // DRAM
        .dram_addr  (dram_addr),
        .dram_req   (dram_req),
        .dram_we    (dram_we),
        .dram_be    (dram_be),
        .dram_wdata (dram_wdata),
        .dram_rdata (dram_rdata),
        .dram_ready (dram_ready),
        // Flash
        .flash_addr (flash_addr),
        .flash_req  (flash_req),
        .flash_rdata(flash_rdata),
        .flash_ready(flash_ready),
        // UART
        .uart_addr  (uart_addr),
        .uart_req   (uart_req),
        .uart_we    (uart_we),
        .uart_be    (uart_be),
        .uart_wdata (uart_wdata),
        .uart_rdata (uart_rdata),
        .uart_ready (uart_ready)
    );

    // ========== IRAM (16KB) ==========
    iram u_iram (
        .clk        (clk),
        // I-port (read-only, for instruction fetch)
        .i_addr     (iram_i_addr),
        .i_req      (iram_i_req),
        .i_rdata    (iram_i_rdata),
        .i_ready    (iram_i_ready),
        // D-port (read/write, for data access)
        .d_addr     (iram_d_addr),
        .d_req      (iram_d_req),
        .d_we       (iram_d_we),
        .d_be       (iram_d_be),
        .d_wdata    (iram_d_wdata),
        .d_rdata    (iram_d_rdata),
        .d_ready    (iram_d_ready)
    );

    // ========== DRAM (8KB) ==========
    dram u_dram (
        .clk        (clk),
        .rst        (rst),
        .addr       (dram_addr),
        .req        (dram_req),
        .we         (dram_we),
        .be         (dram_be),
        .wdata      (dram_wdata),
        .rdata      (dram_rdata),
        .ready      (dram_ready)
    );

    // ========== Flash Controller (XIP) ==========
    flash_ctrl u_flash (
        .clk        (clk),
        .rst        (rst),
        .addr       (flash_addr),
        .req        (flash_req),
        .rdata      (flash_rdata),
        .ready      (flash_ready)
    );

    // ========== UART ==========
    uart_perip u_uart (
        .clk        (clk),
        .rst        (rst),
        .addr       (uart_addr),
        .req        (uart_req),
        .we         (uart_we),
        .be         (uart_be),
        .wdata      (uart_wdata),
        .rdata      (uart_rdata),
        .ready      (uart_ready),
        .rx         (uart_rx),
        .tx         (uart_tx)
    );

    // ========== LEDs ==========
    assign led = {rst, 3'b0, uart_rx, uart_tx};

endmodule
