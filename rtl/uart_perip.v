// UART Peripheral - 115200 baud, 8N1

module uart_perip (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] addr,
    input  wire        req,
    input  wire        we,
    input  wire [3:0]  be,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output reg         ready,
    input  wire        rx,
    output reg         tx
);

    // Registers
    reg [7:0]   tx_data;
    reg         tx_busy;
    reg [7:0]   rx_data;
    reg         rx_valid;
    reg [15:0]  divisor;

    localparam ADDR_TX    = 2'b00;
    localparam ADDR_RX    = 2'b01;
    localparam ADDR_STAT  = 2'b10;
    localparam ADDR_DIV   = 2'b11;

    // Status register
    wire [7:0] status = {6'b0, rx_valid, tx_busy};

    // Read
    always @(*) begin
        case (addr[3:2])
            ADDR_TX:   rdata = {24'b0, tx_data};
            ADDR_RX:   rdata = {24'b0, rx_data};
            ADDR_STAT: rdata = {24'b0, status};
            ADDR_DIV:  rdata = {16'b0, divisor};
            default:   rdata = 32'h0;
        endcase
        ready = req;
    end

    // Write
    always @(posedge clk) begin
        if (rst) begin
            divisor <= 16'd234;  // 27MHz / 115200
            tx_busy <= 1'b0;
        end else if (req && we) begin
            case (addr[3:2])
                ADDR_TX:   tx_data <= wdata[7:0];
                ADDR_DIV:  divisor <= wdata[15:0];
                default: ;
            endcase
        end
    end

    // TX state machine
    localparam TX_IDLE  = 2'b00;
    localparam TX_START = 2'b01;
    localparam TX_DATA  = 2'b10;
    localparam TX_STOP  = 2'b11;

    reg [1:0]  tx_state;
    reg [15:0] tx_counter;
    reg [7:0]  tx_shift;

    always @(posedge clk) begin
        if (rst) begin
            tx <= 1'b1;
            tx_state <= TX_IDLE;
            tx_busy <= 1'b0;
            tx_counter <= 16'd0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    tx_counter <= 16'd0;
                    if (req && we && addr[3:2] == ADDR_TX) begin
                        tx_shift <= wdata[7:0];
                        tx_busy <= 1'b1;
                        tx_state <= TX_START;
                    end
                end
                TX_START: begin
                    tx <= 1'b0;
                    if (tx_counter >= divisor - 1) begin
                        tx_counter <= 16'd0;
                        tx_state <= TX_DATA;
                    end else begin
                        tx_counter <= tx_counter + 1;
                    end
                end
                TX_DATA: begin
                    tx <= tx_shift[0];
                    if (tx_counter >= divisor - 1) begin
                        tx_counter <= 16'd0;
                        tx_shift <= {1'b0, tx_shift[7:1]};
                        if (tx_shift[7:1] == 7'b0) begin
                            tx_state <= TX_STOP;
                        end
                    end else begin
                        tx_counter <= tx_counter + 1;
                    end
                end
                TX_STOP: begin
                    tx <= 1'b1;
                    if (tx_counter >= divisor - 1) begin
                        tx_counter <= 16'd0;
                        tx_state <= TX_IDLE;
                        tx_busy <= 1'b0;
                    end else begin
                        tx_counter <= tx_counter + 1;
                    end
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // RX state machine
    localparam RX_IDLE  = 2'b00;
    localparam RX_START = 2'b01;
    localparam RX_DATA  = 2'b10;
    localparam RX_STOP  = 2'b11;

    reg [1:0]  rx_state;
    reg [15:0] rx_counter;
    reg [7:0]  rx_shift;

    always @(posedge clk) begin
        if (rst) begin
            rx_valid <= 1'b0;
            rx_data <= 8'h0;
            rx_state <= RX_IDLE;
            rx_counter <= 16'd0;
        end else begin
            case (rx_state)
                RX_IDLE: begin
                    rx_valid <= 1'b0;
                    if (rx == 1'b0) begin
                        rx_state <= RX_START;
                        rx_counter <= 16'd0;
                    end
                end
                RX_START: begin
                    if (rx_counter >= divisor / 2) begin
                        if (rx == 1'b0) begin
                            rx_counter <= 16'd0;
                            rx_state <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_counter <= rx_counter + 1;
                    end
                end
                RX_DATA: begin
                    if (rx_counter >= divisor - 1) begin
                        rx_counter <= 16'd0;
                        rx_shift <= {rx, rx_shift[7:1]};
                        if (rx_shift[7:1] == 7'b0) begin
                            rx_data <= {rx, rx_shift[7:1]};
                            rx_state <= RX_STOP;
                        end
                    end else begin
                        rx_counter <= rx_counter + 1;
                    end
                end
                RX_STOP: begin
                    if (rx_counter >= divisor - 1) begin
                        rx_counter <= 16'd0;
                        rx_data <= rx_shift;
                        rx_valid <= 1'b1;
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_counter <= rx_counter + 1;
                    end
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule
