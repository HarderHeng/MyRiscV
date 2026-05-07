// Bus Matrix - AHB-Lite Interconnect

module bus (
    input  wire        clk,
    input  wire        rst,
    // CPU I-BUS
    input  wire [31:0] i_addr,
    input  wire        i_req,
    output reg  [31:0] i_rdata,
    output reg         i_ready,
    // CPU D-BUS
    input  wire [31:0] d_addr,
    input  wire        d_req,
    input  wire        d_we,
    input  wire [3:0]  d_be,
    input  wire [31:0] d_wdata,
    output reg  [31:0] d_rdata,
    output reg         d_ready,
    // IRAM I-port
    output wire [31:0] iram_i_addr,
    output wire        iram_i_req,
    input  wire [31:0] iram_i_rdata,
    input  wire        iram_i_ready,
    // IRAM D-port
    output wire [31:0] iram_d_addr,
    output wire        iram_d_req,
    output wire        iram_d_we,
    output wire [3:0]  iram_d_be,
    output wire [31:0] iram_d_wdata,
    input  wire [31:0] iram_d_rdata,
    input  wire        iram_d_ready,
    // DRAM
    output wire [31:0] dram_addr,
    output wire        dram_req,
    output wire        dram_we,
    output wire [3:0]  dram_be,
    output wire [31:0] dram_wdata,
    input  wire [31:0] dram_rdata,
    input  wire        dram_ready,
    // Flash
    output wire [31:0] flash_addr,
    output wire        flash_req,
    input  wire [31:0] flash_rdata,
    input  wire        flash_ready,
    // UART
    output wire [31:0] uart_addr,
    output wire        uart_req,
    output wire        uart_we,
    output wire [3:0]  uart_be,
    output wire [31:0] uart_wdata,
    input  wire [31:0] uart_rdata,
    input  wire        uart_ready
);

    // I-BUS address decode
    wire iram_i_sel = (i_addr >= 32'h80000000) && (i_addr < 32'h80004000);
    wire flash_sel  = (i_addr >= 32'h20000000) && (i_addr < 32'h20130000);

    // D-BUS address decode
    wire iram_d_sel = (d_addr >= 32'h80000000) && (d_addr < 32'h80004000);
    wire dram_sel   = (d_addr >= 32'h80004000) && (d_addr < 32'h80006000);
    wire uart_sel   = (d_addr >= 32'h10000000) && (d_addr < 32'h10010000);

    // I-BUS multiplexor
    always @(*) begin
        iram_i_addr = i_addr;
        iram_i_req = 1'b0;
        i_rdata = 32'h0;
        i_ready = 1'b0;

        flash_addr = i_addr;
        flash_req = 1'b0;

        if (i_req) begin
            if (iram_i_sel) begin
                iram_i_addr = i_addr;
                iram_i_req = 1'b1;
                i_rdata = iram_i_rdata;
                i_ready = iram_i_ready;
            end else if (flash_sel) begin
                flash_addr = i_addr;
                flash_req = 1'b1;
                i_rdata = flash_rdata;
                i_ready = flash_ready;
            end
        end
    end

    // D-BUS multiplexor
    always @(*) begin
        iram_d_addr = d_addr;
        iram_d_req = 1'b0;
        iram_d_we = 1'b0;
        iram_d_be = 4'h0;
        iram_d_wdata = 32'h0;

        dram_addr = d_addr;
        dram_req = 1'b0;
        dram_we = 1'b0;
        dram_be = 4'h0;
        dram_wdata = 32'h0;

        uart_addr = d_addr;
        uart_req = 1'b0;
        uart_we = 1'b0;
        uart_be = 4'h0;
        uart_wdata = 32'h0;

        d_rdata = 32'h0;
        d_ready = 1'b0;

        if (d_req) begin
            if (iram_d_sel) begin
                iram_d_addr = d_addr;
                iram_d_req = 1'b1;
                iram_d_we = d_we;
                iram_d_be = d_be;
                iram_d_wdata = d_wdata;
                d_rdata = iram_d_rdata;
                d_ready = iram_d_ready;
            end else if (dram_sel) begin
                dram_addr = d_addr;
                dram_req = 1'b1;
                dram_we = d_we;
                dram_be = d_be;
                dram_wdata = d_wdata;
                d_rdata = dram_rdata;
                d_ready = dram_ready;
            end else if (uart_sel) begin
                uart_addr = d_addr;
                uart_req = 1'b1;
                uart_we = d_we;
                uart_be = d_be;
                uart_wdata = d_wdata;
                d_rdata = uart_rdata;
                d_ready = uart_ready;
            end
        end
    end

endmodule
