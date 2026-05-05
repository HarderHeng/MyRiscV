`ifndef AHBLITE_BUS_SV
`define AHBLITE_BUS_SV

// ============================================================
//  AHB-Lite Bus Matrix - 简化版
//
//  单主设备(CPU) / 4从设备(IRAM, DRAM, Flash, Peripherals)
//  地址映射:
//    0x1000_xxxx  Peripherals (UART, GPIO)
//    0x2000_xxxx  Flash (XIP)
//    0x8000_0000 - 0x8000_3FFF  IRAM (16KB)
//    0x8000_4000 - 0x8000_5FFF  DRAM (8KB)
//
//  特性:
//    - 组合逻辑地址解码
//    - 单周期延迟
//    - 无 BURST 支持
// ============================================================
module AHB_Lite_Bus (
    input  wire        clk,
    input  wire        rst,

    // ========== Master Interface (CPU) ==========
    input  wire [31:0] haddr_m,      // Address
    input  wire        hsel_m,        // Master select (always 1 for now)
    input  wire        hready_m,      // Master ready for next transfer
    input  wire [1:0]  htrans_m,     // Transfer type (NONSEQ=2, SEQ=3, IDLE=0)
    input  wire        hwrite_m,      // Write enable
    input  wire [2:0]  hsize_m,      // Size (0=8bit, 1=16bit, 2=32bit)
    input  wire [3:0]  hstrb_m,      // Byte strobe
    input  wire [31:0] hwdata_m,     // Write data
    output wire [31:0] hrdata_m,      // Read data
    output wire        hreadyout_m,   // Transfer complete
    output wire        hresp_m,       // Response (0=OK, 1=ERROR)

    // ========== Slave 0: IRAM (0x8000_0000 - 0x8000_3FFF) ==========
    output wire [31:0] s0_addr,
    output wire        s0_ren,
    output wire        s0_wen,
    output wire [3:0]  s0_be,
    output wire [31:0] s0_wdata,
    input  wire [31:0] s0_rdata,
    input  wire        s0_ready,

    // ========== Slave 1: DRAM (0x8000_4000 - 0x8000_5FFF) ==========
    output wire [31:0] s1_addr,
    output wire        s1_ren,
    output wire        s1_wen,
    output wire [3:0]  s1_be,
    output wire [31:0] s1_wdata,
    input  wire [31:0] s1_rdata,
    input  wire        s1_ready,

    // ========== Slave 2: Flash (0x2000_0000 - 0x2012_FFFF) ==========
    output wire [31:0] s2_addr,
    output wire        s2_ren,
    output wire        s2_wen,
    output wire [3:0]  s2_be,
    output wire [31:0] s2_wdata,
    input  wire [31:0] s2_rdata,
    input  wire        s2_ready,

    // ========== Slave 3: Peripherals (0x1000_0000 - 0x1000_FFFF) ==========
    output wire [31:0] s3_addr,
    output wire        s3_ren,
    output wire        s3_wen,
    output wire [3:0]  s3_be,
    output wire [31:0] s3_wdata,
    input  wire [31:0] s3_rdata,
    input  wire        s3_ready
);

    // ============================================================
    //  地址解码
    // ============================================================

    // 地址区域判断（使用高位）
    wire is_sram    = (haddr_m[31:28] == 4'h8);   // 0x8000_xxxx
    wire is_flash   = (haddr_m[31:28] == 4'h2);   // 0x2000_xxxx
    wire is_periph  = (haddr_m[31:28] == 4'h1);   // 0x1000_xxxx

    // SRAM 内部解析：IRAM vs DRAM
    wire is_iram    = is_sram && (haddr_m[14] == 1'b0);  // 0x8000_0000 - 0x8000_3FFF
    wire is_dram    = is_sram && (haddr_m[14] == 1'b1);  // 0x8000_4000 - 0x8000_5FFF

    // 从设备选择
    wire sel_iram   = is_iram;
    wire sel_dram   = is_dram;
    wire sel_flash  = is_flash;
    wire sel_periph = is_periph;

    // 有效传输检测（hsel 且 htrans != IDLE）
    wire valid_trans = hsel_m && (htrans_m != 2'b00);

    // ============================================================
    //  从设备信号分配
    // ============================================================

    // IRAM (Slave 0)
    assign s0_addr   = haddr_m;
    assign s0_ren    = valid_trans && !hwrite_m && sel_iram;
    assign s0_wen    = valid_trans && hwrite_m && sel_iram;
    assign s0_be     = hstrb_m;
    assign s0_wdata  = hwdata_m;

    // DRAM (Slave 1)
    assign s1_addr   = haddr_m;
    assign s1_ren    = valid_trans && !hwrite_m && sel_dram;
    assign s1_wen    = valid_trans && hwrite_m && sel_dram;
    assign s1_be     = hstrb_m;
    assign s1_wdata  = hwdata_m;

    // Flash (Slave 2)
    assign s2_addr   = haddr_m;
    assign s2_ren    = valid_trans && !hwrite_m && sel_flash;
    assign s2_wen    = valid_trans && hwrite_m && sel_flash;
    assign s2_be     = hstrb_m;
    assign s2_wdata  = hwdata_m;

    // Peripherals (Slave 3)
    assign s3_addr   = haddr_m;
    assign s3_ren    = valid_trans && !hwrite_m && sel_periph;
    assign s3_wen    = valid_trans && hwrite_m && sel_periph;
    assign s3_be     = hstrb_m;
    assign s3_wdata  = hwdata_m;

    // ============================================================
    //  主设备数据返回 (HRDATA)
    // ============================================================

    reg [31:0] hrdata_r;
    always @(*) begin
        if (sel_iram)    hrdata_r = s0_rdata;
        else if (sel_dram)   hrdata_r = s1_rdata;
        else if (sel_flash)  hrdata_r = s2_rdata;
        else if (sel_periph) hrdata_r = s3_rdata;
        else                 hrdata_r = 32'h0;
    end
    assign hrdata_m = hrdata_r;

    // ============================================================
    //  从设备就绪信号 (HREADYOUT)
    //  所有从设备当前都是单周期访问
    // ============================================================

    wire hready_iram   = s0_ready;
    wire hready_dram   = s1_ready;
    wire hready_flash  = s2_ready;
    wire hready_periph = s3_ready;

    // 组合所有就绪信号
    assign hreadyout_m = sel_iram   ? hready_iram   :
                         sel_dram   ? hready_dram   :
                         sel_flash  ? hready_flash  :
                         sel_periph ? hready_periph :
                                      1'b1;  // 无选择时直接完成

    // ============================================================
    //  响应信号 (HRESP)
    //  0 = OKAY, 1 = ERROR
    //  当前所有访问都返回 OKAY
    // ============================================================

    assign hresp_m = 1'b0;  // 始终 OKAY

endmodule

`endif // AHBLITE_BUS_SV
