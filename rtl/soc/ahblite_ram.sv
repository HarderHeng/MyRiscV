`ifndef AHBLITE_RAM_SV
`define AHBLITE_RAM_SV

// ============================================================
//  AHB-Lite RAM Wrapper - 将 IRAM/DRAM 接口转换为 AHB-Lite 从设备
//
//  将 AHB-Lite 传输转换为现有 RAM 接口信号
// ============================================================
module AHB_Lite_RAM (
    input  wire        hclk,
    input  wire        hresetn,

    // AHB-Lite Slave Interface
    input  wire [31:0] haddr,
    input  wire        hsel,
    input  wire        hready_in,
    input  wire [1:0]  htrans,
    input  wire        hwrite,
    input  wire [2:0]  hsize,
    input  wire [3:0]  hstrb,
    input  wire [31:0] hwdata,
    output reg  [31:0] hrdata,
    output reg         hreadyout,
    output reg         hresp,

    // RAM Interface
    output wire [31:0] ram_addr,
    output wire        ram_ren,
    output wire        ram_wen,
    output wire [3:0]  ram_be,
    output wire [31:0] ram_wdata,
    input  wire [31:0] ram_rdata,
    input  wire        ram_ready
);

    // ============================================================
    //  传输检测
    // ============================================================
    wire valid_trans = hsel && hready_in && (htrans == 2'b10);

    // ============================================================
    //  读写使能
    // ============================================================
    wire read_req = valid_trans && !hwrite;
    wire write_req = valid_trans && hwrite;

    // ============================================================
    //  RAM 信号
    // ============================================================
    assign ram_addr = {haddr[31:2], 2'b00};  // 字对齐
    assign ram_ren = read_req;
    assign ram_wen = write_req;
    assign ram_be = hstrb;
    assign ram_wdata = hwdata;

    // ============================================================
    //  读数据
    // ============================================================
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            hrdata <= 32'h0;
        end else if (ram_ready) begin
            hrdata <= ram_rdata;
        end
    end

    // ============================================================
    //  就绪和响应
    // ============================================================
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            hreadyout <= 1'b1;
            hresp <= 1'b0;
        end else begin
            hreadyout <= ram_ready;
            hresp <= 1'b0;  // OK
        end
    end

endmodule

`endif // AHBLITE_RAM_SV
