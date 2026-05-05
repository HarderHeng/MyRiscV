`ifndef BUS_MATRIX_SV
`define BUS_MATRIX_SV

// ============================================================
//  AHB-Lite Bus Matrix
//  支持主设备: ICache, DCache, Debug Module
//  从设备: IRAM, DRAM, Peripheral, SPI_XIP, Flash
// ============================================================

module BusMatrix (
    input  wire        clk,
    input  wire        rst,

    // ---------- 主设备端口 ----------
    // ICache (指令取指)
    input  wire [31:0] haddr_i,      // ICache 地址
    input  wire        hready_i,      // ICache 就绪
    input  wire        hsel_i,        // ICache 选中
    output wire [31:0] hrdata_i,     // ICache 读数据
    output wire        hresp_i,       // ICache 响应

    // DCache (数据访问)
    input  wire [31:0] haddr_d,      // DCache 地址
    input  wire        hready_d,      // DCache 就绪
    input  wire        hsel_d,        // DCache 选中
    input  wire        hwrite_d,      // DCache 写使能
    input  wire [3:0]  hstrb_d,      // DCache 字节使能
    input  wire [31:0] hwdata_d,    // DCache 写数据
    output wire [31:0] hrdata_d,    // DCache 读数据
    output wire        hresp_d,      // DCache 响应

    // Debug Module (SBA访问)
    input  wire [31:0] haddr_dm,     // DM 地址
    input  wire        hready_dm,     // DM 就绪
    input  wire        hsel_dm,       // DM 选中
    input  wire        hwrite_dm,     // DM 写使能
    input  wire [3:0]  hstrb_dm,    // DM 字节使能
    input  wire [31:0] hwdata_dm,    // DM 写数据
    output wire [31:0] hrdata_dm,   // DM 读数据
    output wire        hresp_dm,      // DM 响应

    // ---------- 从设备端口 ----------
    // IRAM (0x8000_0000 ~ 0x8000_3FFF)
    output wire [31:0] iram_addr,
    output wire        iram_ren,
    output wire        iram_wen,
    output wire [3:0]  iram_be,
    output wire [31:0] iram_wdata,
    input  wire [31:0] iram_rdata,

    // DRAM (0x8000_4000 ~ 0x8000_5FFF)
    output wire [31:0] dram_addr,
    output wire        dram_ren,
    output wire        dram_wen,
    output wire [3:0]  dram_be,
    output wire [31:0] dram_wdata,
    input  wire [31:0] dram_rdata,

    // Peripherals (0x1000_0000 ~ 0x1000_FFFF)
    output wire [31:0] periph_addr,
    output wire        periph_ren,
    output wire        periph_wen,
    output wire [3:0]  periph_be,
    output wire [31:0] periph_wdata,
    input  wire [31:0] periph_rdata,

    // SPI_XIP (0x1000_3000 ~ 0x1000_3FFF 映射外部SPI Flash)
    output wire [31:0] spi_xip_addr,
    output wire        spi_xip_ren,
    output wire        spi_xip_wen,
    output wire [3:0]  spi_xip_be,
    output wire [31:0] spi_xip_wdata,
    input  wire [31:0] spi_xip_rdata,

    // Flash (0x2000_0000 ~ 0x2012_FFFF)
    output wire [31:0] flash_addr,
    output wire        flash_ren,
    output wire        flash_wen,
    output wire [3:0]  flash_be,
    output wire [31:0] flash_wdata,
    input  wire [31:0] flash_rdata
);

// ============================================================
//  地址译码
// ============================================================

// 地址区域定义
localparam ADDR_IRAM    = 3'b000;  // 0x8000_0000
localparam ADDR_DRAM    = 3'b001;  // 0x8000_4000
localparam ADDR_PERIPH  = 3'b010;  // 0x1000_0000
localparam ADDR_SPI_XIP = 3'b011;  // 0x1000_3000
localparam ADDR_FLASH   = 3'b100;  // 0x2000_0000
localparam ADDR_INVALID = 3'b111;

// 地址解码
function automatic [2:0] addr_decode(input [31:0] addr);
    casez (addr[31:16])
        16'h1000: begin
            if (addr[15:12] == 4'h3)
                return ADDR_SPI_XIP;  // 0x1000_3000 ~ 0x1000_3FFF
            else
                return ADDR_PERIPH;    // 0x1000_0000 ~ 0x1000_2FFF
        end
        16'h2000: return ADDR_FLASH;  // 0x2000_0000
        16'h8000: begin
            if (addr[15:13] == 3'b000)
                return ADDR_IRAM;     // 0x8000_0000 ~ 0x8000_3FFF
            else
                return ADDR_DRAM;      // 0x8000_4000 ~ 0x8000_FFFF
        end
        default: return ADDR_INVALID;
    endcase
endfunction

// ============================================================
//  仲裁
// ============================================================

// 优先级: DM > DCache > ICache
wire [2:0] i_sel = addr_decode(haddr_i);
wire [2:0] d_sel = addr_decode(haddr_d);
wire [2:0] dm_sel = addr_decode(haddr_dm);

// DM 优先级最高
wire dm_active = hsel_dm && hready_dm;
wire d_active = hsel_d && hready_d && !dm_active;
wire i_active = hsel_i && hready_i && !dm_active && !d_active;

// ============================================================
//  从设备选择信号
// ============================================================

wire sel_iram    = (i_sel == ADDR_IRAM) || (d_sel == ADDR_IRAM) || (dm_sel == ADDR_IRAM);
wire sel_dram    = (i_sel == ADDR_DRAM) || (d_sel == ADDR_DRAM) || (dm_sel == ADDR_DRAM);
wire sel_periph  = (i_sel == ADDR_PERIPH) || (d_sel == ADDR_PERIPH) || (dm_sel == ADDR_PERIPH);
wire sel_spi_xip = (i_sel == ADDR_SPI_XIP) || (d_sel == ADDR_SPI_XIP) || (dm_sel == ADDR_SPI_XIP);
wire sel_flash   = (i_sel == ADDR_FLASH) || (d_sel == ADDR_FLASH) || (dm_sel == ADDR_FLASH);

// ============================================================
//  地址和数据选通
// ============================================================

// 选择当前主设备的地址
wire [31:0] current_addr = dm_active ? haddr_dm :
                           d_active ? haddr_d :
                           i_active ? haddr_i : 32'h0;

wire current_write = dm_active ? hwrite_dm :
                     d_active ? hwrite_d : 1'b0;

wire [3:0] current_be = dm_active ? hstrb_dm :
                        d_active ? hstrb_d : 4'hF;

wire [31:0] current_wdata = dm_active ? hwdata_dm :
                             d_active ? hwdata_d : 32'h0;

// ============================================================
//  从设备信号驱动
// ============================================================

// IRAM
assign iram_addr   = sel_iram ? current_addr : 32'h0;
assign iram_ren    = sel_iram && !current_write;
assign iram_wen    = sel_iram && current_write;
assign iram_be     = sel_iram ? current_be : 4'h0;
assign iram_wdata  = sel_iram ? current_wdata : 32'h0;

// DRAM
assign dram_addr   = sel_dram ? current_addr : 32'h0;
assign dram_ren   = sel_dram && !current_write;
assign dram_wen   = sel_dram && current_write;
assign dram_be    = sel_dram ? current_be : 4'h0;
assign dram_wdata = sel_dram ? current_wdata : 32'h0;

// Peripherals
assign periph_addr   = sel_periph ? current_addr : 32'h0;
assign periph_ren    = sel_periph && !current_write;
assign periph_wen    = sel_periph && current_write;
assign periph_be     = sel_periph ? current_be : 4'h0;
assign periph_wdata  = sel_periph ? current_wdata : 32'h0;

// SPI_XIP
assign spi_xip_addr   = sel_spi_xip ? current_addr : 32'h0;
assign spi_xip_ren    = sel_spi_xip && !current_write;
assign spi_xip_wen    = sel_spi_xip && current_write;
assign spi_xip_be     = sel_spi_xip ? current_be : 4'h0;
assign spi_xip_wdata  = sel_spi_xip ? current_wdata : 32'h0;

// Flash
assign flash_addr   = sel_flash ? current_addr : 32'h0;
assign flash_ren    = sel_flash && !current_write;
assign flash_wen    = sel_flash && current_write;
assign flash_be     = sel_flash ? current_be : 4'h0;
assign flash_wdata  = sel_flash ? current_wdata : 32'h0;

// ============================================================
//  读数据选通
// ============================================================

reg [31:0] i_rdata_r, d_rdata_r, dm_rdata_r;
reg i_resp_r, d_resp_r, dm_resp_r;

// ICache 读数据
always @(*) begin
    if (sel_iram) i_rdata_r = iram_rdata;
    else if (sel_dram) i_rdata_r = dram_rdata;
    else if (sel_periph) i_rdata_r = periph_rdata;
    else if (sel_spi_xip) i_rdata_r = spi_xip_rdata;
    else if (sel_flash) i_rdata_r = flash_rdata;
    else i_rdata_r = 32'h0;
end

// DCache 读数据
always @(*) begin
    if (sel_iram) d_rdata_r = iram_rdata;
    else if (sel_dram) d_rdata_r = dram_rdata;
    else if (sel_periph) d_rdata_r = periph_rdata;
    else if (sel_spi_xip) d_rdata_r = spi_xip_rdata;
    else if (sel_flash) d_rdata_r = flash_rdata;
    else d_rdata_r = 32'h0;
end

// DM 读数据
always @(*) begin
    if (sel_iram) dm_rdata_r = iram_rdata;
    else if (sel_dram) dm_rdata_r = dram_rdata;
    else if (sel_periph) dm_rdata_r = periph_rdata;
    else if (sel_spi_xip) dm_rdata_r = spi_xip_rdata;
    else if (sel_flash) dm_rdata_r = flash_rdata;
    else dm_rdata_r = 32'h0;
end

// 响应
always @(*) begin
    i_resp_r = i_active && (i_sel == ADDR_INVALID);
    d_resp_r = d_active && (d_sel == ADDR_INVALID);
    dm_resp_r = dm_active && (dm_sel == ADDR_INVALID);
end

assign hrdata_i = i_rdata_r;
assign hresp_i  = i_resp_r;

assign hrdata_d = d_rdata_r;
assign hresp_d  = d_resp_r;

assign hrdata_dm = dm_rdata_r;
assign hresp_dm  = dm_resp_r;

endmodule

`endif // BUS_MATRIX_SV
