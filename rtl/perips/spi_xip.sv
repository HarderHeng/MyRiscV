`ifndef SPI_XIP_SV
`define SPI_XIP_SV

// ============================================================
//  SPI XIP - External SPI Flash Mapping
//
//  Maps external SPI flash into address space 0x1000_3000-0x1000_3FFF
//  For Tang Nano 9K, this is typically a placeholder since
//  the device uses internal Gowin flash.
//
//  Features:
//    - Read-only XIP access to external SPI flash
//    - Supports 1-1-1, 1-1-2, 1-1-4, 1-4-4 read modes
//    - Wishbone/AHB-Lite compatible interface
//
//  This is a stub implementation that returns zeros.
//  To be extended when actual external SPI flash is added.
// ============================================================
module SpiXip (
    input  wire        clk,
    input  wire        rst,

    // AHB-Lite slave interface
    input  wire [31:0] haddr,
    input  wire        hsel,
    input  wire        hready,
    input  wire        hwrite,
    input  wire [3:0]  hstrb,
    input  wire [31:0] hwdata,

    output reg  [31:0] hrdata,
    output reg         hresp
);

    // SPI flash is read-only
    wire ren = hsel && hready && !hwrite;
    wire wen = hsel && hready && hwrite;

    // Address offset within SPI XIP region
    wire [13:0] xip_offset = haddr[13:0];

    // SPI flash read data register
    reg [31:0] spi_rdata;

    // State machine for SPI read (simplified)
    localparam S_IDLE  = 1'b0;
    localparam S_READY = 1'b1;

    reg state;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            hrdata <= 32'h0;
            hresp <= 1'b0;
            spi_rdata <= 32'h0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (ren) begin
                        // SPI flash read - return zeros for stub
                        spi_rdata <= 32'h0;
                        hrdata <= 32'h0;  // Return zeros for now
                        state <= S_READY;
                    end else begin
                        state <= S_IDLE;
                    end
                end

                S_READY: begin
                    hrdata <= spi_rdata;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Writes are ignored (read-only XIP)
    always @(posedge clk) begin
        if (rst) begin
            hresp <= 1'b0;
        end else begin
            hresp <= 1'b0;  // Always OKAY
        end
    end

endmodule

`endif // SPI_XIP_SV