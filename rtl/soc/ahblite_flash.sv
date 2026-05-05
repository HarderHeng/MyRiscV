`ifndef AHBLITE_FLASH_SV
`define AHBLITE_FLASH_SV

// ============================================================
//  AHB-Lite Flash Wrapper - 将 FlashCtrl 接口转换为 AHB-Lite 从设备
//
//  Flash 特性:
//    - 2周期读取延迟
//    - 组合读（仿真模式）或状态机读（综合模式）
// ============================================================
module AHB_Lite_Flash (
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

    // Flash Interface
    input  wire [31:0] flash_rdata,
    input  wire        flash_rdata_vld,
    output wire [31:0] flash_addr,
    output wire        flash_ren,
    output wire        flash_wen
);

    // ============================================================
    //  传输检测
    // ============================================================
    wire valid_trans = hsel && hready_in && (htrans == 2'b10);

    // ============================================================
    //  Flash 信号
    // ============================================================
    assign flash_addr = {haddr[31:2], 2'b00};  // 字对齐
    assign flash_ren = valid_trans && !hwrite;
    assign flash_wen = valid_trans && hwrite;  // Flash 通常不支持写

    // ============================================================
    //  读数据
    // ============================================================
    `ifdef SYNTHESIS
    // 综合模式：状态机处理
    reg [1:0] state;
    localparam S_IDLE = 2'b00;
    localparam S_READ = 2'b01;
    localparam S_READY = 2'b10;

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            state <= S_IDLE;
            hrdata <= 32'h0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (flash_ren) begin
                        state <= S_READ;
                        hrdata <= 32'h0;
                    end
                end
                S_READ: begin
                    if (flash_rdata_vld) begin
                        hrdata <= flash_rdata;
                        state <= S_READY;
                    end
                end
                S_READY: begin
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    always @(*) begin
        case (state)
            S_IDLE:  hreadyout = 1'b1;
            S_READ:  hreadyout = 1'b0;  // 等待
            S_READY: hreadyout = 1'b1;
            default: hreadyout = 1'b1;
        endcase
    end

    `else
    // 仿真模式：组合逻辑
    always @(*) begin
        hrdata = flash_rdata;
        hreadyout = 1'b1;
    end
    `endif

    // ============================================================
    //  响应
    // ============================================================
    always @(*) begin
        hresp = 1'b0;  // OK
    end

endmodule

`endif // AHBLITE_FLASH_SV
