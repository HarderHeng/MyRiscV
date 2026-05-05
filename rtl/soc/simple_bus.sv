`ifndef SIMPLE_BUS_SV
`define SIMPLE_BUS_SV

// ============================================================
//  SimpleBus - 极简地址选择器
//
//  地址映射:
//    0x1000_xxxx  外设空间
//    0x2000_xxxx  Flash (XIP, 复位后从这里取指)
//    0x8000_xxxx  SRAM区域
// ============================================================
module SimpleBus (
    input  wire        clk,

    // CPU 指令接口
    input  wire [31:0] i_addr,
    output wire [31:0] i_rdata,

    // CPU 数据接口
    input  wire [31:0] d_addr,
    input  wire        d_req,
    input  wire        d_we,
    input  wire [3:0]  d_be,
    input  wire [31:0] d_wdata,
    output wire [31:0] d_rdata,

    // IRAM
    input  wire [31:0] iram_rdata,

    // DRAM
    input  wire [31:0] dram_rdata,

    // Peripherals
    input  wire [31:0] periph_rdata,

    // Flash
    input  wire [31:0] flash_rdata
);

    // ============================================================
    //  指令读取 - 直接根据地址选择
    // ============================================================
    wire i_is_flash = (i_addr[31:16] == 16'h2000);  // 0x2000xxxx
    wire i_is_iram  = (i_addr[31:16] == 16'h8000) && !i_is_flash;  // 0x8000xxxx but not flash

    assign i_rdata = i_is_flash ? flash_rdata :
                     i_is_iram  ? iram_rdata : 32'h0;

    // ============================================================
    //  数据读取
    // ============================================================
    wire d_is_flash  = (d_addr[31:16] == 16'h2000);
    wire d_is_dram   = (d_addr[31:16] == 16'h8000) && !d_is_flash;
    wire d_is_periph = (d_addr[31:16] == 16'h1000);

    assign d_rdata = d_is_dram   ? dram_rdata :
                     d_is_periph ? periph_rdata :
                     d_is_flash  ? flash_rdata : 32'h0;

endmodule

`endif // SIMPLE_BUS_SV