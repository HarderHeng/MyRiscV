`ifndef GPIO_SV
`define GPIO_SV

// ============================================================
//  GPIO Controller
//  Address: 0x1000_0100 - 0x1000_01FF
//
//  Registers:
//    0x00 DATA  - GPIO Data [31:0]
//    0x04 DIR   - Direction [31:0] (1=output, 0=input)
//    0x08 OUT_EN - Output Enable [31:0]
// ============================================================
module GPIO (
    input  wire        clk,
    input  wire        rst,

    input  wire [1:0]  addr,
    input  wire        wen,
    input  wire        ren,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    output wire [31:0] gpio_out,
    input  wire [31:0] gpio_in
);

    // Registers
    reg [31:0] gpio_data;
    reg [31:0] gpio_dir;
    reg [31:0] gpio_out_en;

    // Write logic
    always @(posedge clk) begin
        if (rst) begin
            gpio_data   <= 32'h0;
            gpio_dir    <= 32'h0;
            gpio_out_en <= 32'h0;
        end else begin
            if (wen) begin
                case (addr)
                    2'b00: gpio_data   <= wdata;
                    2'b01: gpio_dir    <= wdata;
                    2'b10: gpio_out_en <= wdata;
                    default: ;
                endcase
            end
        end
    end

    // Read logic
    always @(posedge clk) begin
        if (rst) begin
            rdata <= 32'h0;
        end else begin
            if (ren) begin
                case (addr)
                    2'b00: rdata <= gpio_in;      // Read actual pin state
                    2'b01: rdata <= gpio_dir;      // Read direction
                    2'b10: rdata <= gpio_out_en;  // Read output enable
                    default: rdata <= 32'h0;
                endcase
            end
        end
    end

    // Output: drive gpio_out when direction is output
    assign gpio_out = gpio_data;

endmodule

`endif // GPIO_SV