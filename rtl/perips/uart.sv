`ifndef UART_SV
`define UART_SV

// ============================================================
//  简单 8N1 UART 控制器
//  波特率：115200 bps @ 27 MHz，分频系数默认 234
//  支持：TX 发送状态机、RX 接收状态机（直接采样，非 16x 过采样）
//  轮询方式，无 FIFO，无中断
// ============================================================
module UART (
    input  wire        clk,
    input  wire        rst,       // 同步高有效复位

    // 总线接口（字对齐地址，只看低 5 位）
    input  wire [4:0]  addr,
    input  wire        wen,
    input  wire        ren,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    // IO
    output wire        uart_tx,
    input  wire        uart_rx
);

// ============================================================
//  寄存器映射（addr[4:2]）
//    3'b000  TXDATA  0x00  W    [7:0] 写入触发发送
//    3'b001  RXDATA  0x04  R    [7:0]=接收数据，[31]=有效
//    3'b010  STATUS  0x08  R    [0]=TX忙，[1]=RX有数据
//    3'b011  DIVISOR 0x0C  R/W  波特率分频（默认234）
// ============================================================

// 波特率分频寄存器（27MHz / 115200 ≈ 234）
reg [15:0] divisor;

// ---------------------------------------------------------
//  TX 状态机
// ---------------------------------------------------------
// TX 状态编码
localparam TX_IDLE  = 4'd0;
localparam TX_START = 4'd1;
localparam TX_D0    = 4'd2;
localparam TX_D1    = 4'd3;
localparam TX_D2    = 4'd4;
localparam TX_D3    = 4'd5;
localparam TX_D4    = 4'd6;
localparam TX_D5    = 4'd7;
localparam TX_D6    = 4'd8;
localparam TX_D7    = 4'd9;
localparam TX_STOP  = 4'd10;

reg [3:0]  tx_state;
reg [7:0]  tx_data;        // 待发送数据寄存器
reg [15:0] tx_clk_cnt;     // 位时钟计数器
reg        tx_out;         // TX 串行输出

// TX 忙标志：非 IDLE 状态即为忙
wire tx_busy = (tx_state != TX_IDLE);

// uart_tx 驱动
assign uart_tx = tx_out;

// TX 时钟域：clk（27 MHz）
always @(posedge clk) begin
    if (rst) begin
        tx_state   <= TX_IDLE;
        tx_clk_cnt <= 16'd0;
        tx_out     <= 1'b1;         // 空闲时为高电平
        tx_data    <= 8'd0;
    end else begin
        case (tx_state)
            TX_IDLE: begin
                tx_out <= 1'b1;
                tx_clk_cnt <= 16'd0;
                // CPU 写 TXDATA 时触发发送
                if (wen && (addr[4:2] == 3'b000)) begin
                    tx_data  <= wdata[7:0];
                    tx_state <= TX_START;
                end
            end

            // 发送起始位（0），持续 divisor 个时钟
            TX_START: begin
                tx_out <= 1'b0;
                if (tx_clk_cnt >= divisor - 1) begin
                    tx_clk_cnt <= 16'd0;
                    tx_state   <= TX_D0;
                end else begin
                    tx_clk_cnt <= tx_clk_cnt + 1;
                end
            end

            // 依次发送数据位 D0~D7（LSB first）
            TX_D0, TX_D1, TX_D2, TX_D3,
            TX_D4, TX_D5, TX_D6, TX_D7: begin
                // 根据当前状态输出对应数据位
                case (tx_state)
                    TX_D0: tx_out <= tx_data[0];
                    TX_D1: tx_out <= tx_data[1];
                    TX_D2: tx_out <= tx_data[2];
                    TX_D3: tx_out <= tx_data[3];
                    TX_D4: tx_out <= tx_data[4];
                    TX_D5: tx_out <= tx_data[5];
                    TX_D6: tx_out <= tx_data[6];
                    TX_D7: tx_out <= tx_data[7];
                    default: tx_out <= 1'b1;
                endcase
                if (tx_clk_cnt >= divisor - 1) begin
                    tx_clk_cnt <= 16'd0;
                    // 状态跳转：D7 → STOP，其余递增
                    if (tx_state == TX_D7)
                        tx_state <= TX_STOP;
                    else
                        tx_state <= tx_state + 1;
                end else begin
                    tx_clk_cnt <= tx_clk_cnt + 1;
                end
            end

            // 发送停止位（1），持续 divisor 个时钟
            TX_STOP: begin
                tx_out <= 1'b1;
                if (tx_clk_cnt >= divisor - 1) begin
                    tx_clk_cnt <= 16'd0;
                    tx_state   <= TX_IDLE;
                end else begin
                    tx_clk_cnt <= tx_clk_cnt + 1;
                end
            end

            default: tx_state <= TX_IDLE;
        endcase
    end
end

// ---------------------------------------------------------
//  RX 状态机（直接采样，在每位中点采样）
// ---------------------------------------------------------
// RX 状态编码
localparam RX_IDLE  = 4'd0;
localparam RX_START = 4'd1;
localparam RX_D0    = 4'd2;
localparam RX_D1    = 4'd3;
localparam RX_D2    = 4'd4;
localparam RX_D3    = 4'd5;
localparam RX_D4    = 4'd6;
localparam RX_D5    = 4'd7;
localparam RX_D6    = 4'd8;
localparam RX_D7    = 4'd9;
localparam RX_STOP  = 4'd10;

reg [3:0]  rx_state;
reg [15:0] rx_clk_cnt;     // 位时钟计数器
reg [7:0]  rx_shift;       // 接收移位寄存器
reg [7:0]  rx_data;        // 接收完成后锁存
reg        rx_valid;       // 接收有效标志（CPU读RXDATA后清除）

// uart_rx 输入两级同步（消除亚稳态）
reg rx_sync0, rx_sync1, rx_sync2;

// RX 时钟域：clk（27 MHz）
always @(posedge clk) begin
    if (rst) begin
        rx_sync0 <= 1'b1;
        rx_sync1 <= 1'b1;
        rx_sync2 <= 1'b1;
    end else begin
        rx_sync0 <= uart_rx;
        rx_sync1 <= rx_sync0;
        rx_sync2 <= rx_sync1;
    end
end

wire rx_in = rx_sync2;  // 同步后的 RX 输入

// RX 半位周期（用于在起始位中点对齐）
wire [15:0] half_div = {1'b0, divisor[15:1]};  // divisor / 2

always @(posedge clk) begin
    if (rst) begin
        rx_state   <= RX_IDLE;
        rx_clk_cnt <= 16'd0;
        rx_shift   <= 8'd0;
        rx_data    <= 8'd0;
        rx_valid   <= 1'b0;
    end else begin
        // CPU 读 RXDATA 后清除有效标志
        if (ren && (addr[4:2] == 3'b001)) begin
            rx_valid <= 1'b0;
        end

        case (rx_state)
            RX_IDLE: begin
                rx_clk_cnt <= 16'd0;
                // 检测下降沿（起始位）
                if (!rx_in) begin
                    rx_state <= RX_START;
                end
            end

            // 等待半个位周期，确认是起始位而非毛刺，然后对齐到中点
            RX_START: begin
                if (rx_clk_cnt >= half_div - 1) begin
                    rx_clk_cnt <= 16'd0;
                    if (!rx_in) begin
                        // 确认是起始位，切换到接收 D0
                        rx_state <= RX_D0;
                    end else begin
                        // 毛刺，回到 IDLE
                        rx_state <= RX_IDLE;
                    end
                end else begin
                    rx_clk_cnt <= rx_clk_cnt + 1;
                end
            end

            // 采样数据位 D0~D7（在每个位周期的中点采样）
            RX_D0, RX_D1, RX_D2, RX_D3,
            RX_D4, RX_D5, RX_D6, RX_D7: begin
                if (rx_clk_cnt >= divisor - 1) begin
                    rx_clk_cnt <= 16'd0;
                    // 在位中点（计数到 divisor-1 时）采样，移入 shift 寄存器
                    // LSB first：D0 先收到，存入 bit0
                    case (rx_state)
                        RX_D0: rx_shift[0] <= rx_in;
                        RX_D1: rx_shift[1] <= rx_in;
                        RX_D2: rx_shift[2] <= rx_in;
                        RX_D3: rx_shift[3] <= rx_in;
                        RX_D4: rx_shift[4] <= rx_in;
                        RX_D5: rx_shift[5] <= rx_in;
                        RX_D6: rx_shift[6] <= rx_in;
                        RX_D7: rx_shift[7] <= rx_in;
                        default: ;
                    endcase
                    if (rx_state == RX_D7)
                        rx_state <= RX_STOP;
                    else
                        rx_state <= rx_state + 1;
                end else begin
                    rx_clk_cnt <= rx_clk_cnt + 1;
                end
            end

            // 停止位：等待 divisor 个时钟，锁存接收数据
            RX_STOP: begin
                if (rx_clk_cnt >= divisor - 1) begin
                    rx_clk_cnt <= 16'd0;
                    rx_state   <= RX_IDLE;
                    if (rx_in) begin
                        // 有效停止位，锁存数据
                        rx_data  <= rx_shift;
                        rx_valid <= 1'b1;
                    end
                    // 无效停止位（帧错误）则丢弃
                end else begin
                    rx_clk_cnt <= rx_clk_cnt + 1;
                end
            end

            default: rx_state <= RX_IDLE;
        endcase
    end
end

// ---------------------------------------------------------
//  分频寄存器写（时钟域：clk）
// ---------------------------------------------------------
always @(posedge clk) begin
    if (rst) begin
        divisor <= 16'd234;  // 27MHz / 115200 ≈ 234
    end else if (wen && (addr[4:2] == 3'b011)) begin
        divisor <= wdata[15:0];
    end
end

// ---------------------------------------------------------
//  总线读（组合逻辑）
// ---------------------------------------------------------
always @(*) begin
    rdata = 32'd0;
    if (ren) begin
        case (addr[4:2])
            3'b001: rdata = {rx_valid, 23'd0, rx_data};  // RXDATA：[31]=有效，[7:0]=数据
            3'b010: rdata = {30'd0, rx_valid, tx_busy};  // STATUS：[0]=TX忙，[1]=RX有数据
            3'b011: rdata = {16'd0, divisor};            // DIVISOR
            default: rdata = 32'd0;
        endcase
    end
end

endmodule

`endif // UART_SV
