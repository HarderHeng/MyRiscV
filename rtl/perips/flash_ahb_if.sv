`ifndef FLASH_AHB_IF_SV
`define FLASH_AHB_IF_SV

// ============================================================
//  FlashAHBIf - Bridge AHB-Lite signals to FlashCtrl
//
//  For simulation (SYNTHESIS not defined):
//    FlashCtrl uses $readmemh and returns data combinatorially
//    irdata_vld = iren (combinational)
//  This module provides proper AHB-Lite compatible response
//
//  For synthesis:
//    FlashCtrl uses FLASH608K原语 with 2-cycle read latency
//    This module handles the timing
// ============================================================
module FlashAHBIf (
    input  wire        clk,
    input  wire        rst,

    // AHB-Lite slave interface (from BusMatrix)
    input  wire [31:0] haddr,
    input  wire        hsel,
    input  wire        hready,
    input  wire        hwrite,
    input  wire [3:0]  hstrb,
    input  wire [31:0] hwdata,

    output reg  [31:0] hrdata,
    output reg         hresp,

    // FlashCtrl interface
    output wire [31:0] flash_iaddr,
    output wire        flash_iren,
    output wire [31:0] flash_cpu_addr,
    output wire        flash_cpu_ren,
    input  wire [31:0] flash_irdata,
    input  wire        flash_irdata_vld,
    input  wire [31:0] flash_cpu_rdata,
    input  wire        flash_cpu_rdata_vld
);

    // Flash is read-only
    wire ren = hsel && hready && !hwrite;

    // Connect directly to instruction port for XIP reads
    assign flash_iaddr    = haddr;
    assign flash_iren     = ren;
    assign flash_cpu_addr = haddr;
    assign flash_cpu_ren  = 1'b0;  // Use instruction port only

    // Register for output
    always @(posedge clk) begin
        if (rst) begin
            hrdata <= 32'h0;
        end else begin
            if (flash_irdata_vld) begin
                hrdata <= flash_irdata;
            end
        end
    end

    // Response is always OKAY
    always @(posedge clk) begin
        if (rst) begin
            hresp <= 1'b0;
        end
    end

endmodule

`endif // FLASH_AHB_IF_SV