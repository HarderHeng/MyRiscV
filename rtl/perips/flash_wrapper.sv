`ifndef FLASH_WRAPPER_SV
`define FLASH_WRAPPER_SV

// ============================================================
//  FlashWrapper - Bridge BusMatrix to FlashCtrl
//
//  BusMatrix provides:
//    flash_addr  - address
//    flash_ren   - read enable
//    flash_wen   - write enable (not used for flash)
//    flash_be    - byte enable
//    flash_wdata - write data (not used for flash)
//
//  FlashCtrl provides:
//    iaddr, iren      - instruction read (XIP)
//    cpu_addr, cpu_ren - data read
//
//  We assume flash_ren includes the sel_flash check already
// ============================================================
module FlashWrapper (
    input  wire        clk,
    input  wire        rst,

    // BusMatrix interface
    input  wire [31:0] flash_addr,
    input  wire        flash_ren,
    input  wire        flash_wen,
    input  wire [3:0]  flash_be,
    input  wire [31:0] flash_wdata,

    // Flash read data (to bus matrix)
    output wire [31:0] flash_rdata,
    output wire        flash_rvalid,

    // FlashCtrl signals (internal)
    output wire [31:0] flash_iaddr,
    output wire        flash_iren,
    output wire [31:0] flash_cpu_addr,
    output wire        flash_cpu_ren
);

    // Flash is read-only, ignore writes
    wire [31:0] flash_rdata_int;
    wire        flash_rvalid_int;

    // Bridge: use flash_addr for both instruction and data accesses
    // based on which read enable is active
    assign flash_iaddr     = flash_addr;
    assign flash_iren       = flash_ren;  // instruction read
    assign flash_cpu_addr   = flash_addr;
    assign flash_cpu_ren    = 1'b0;       // data read not used via this path

    // Return instruction read data
    assign flash_rdata  = flash_rdata_int;
    assign flash_rvalid = flash_rvalid_int;

    // For simulation - FlashCtrl is instantiated separately
    // This wrapper just routes signals

endmodule

`endif // FLASH_WRAPPER_SV