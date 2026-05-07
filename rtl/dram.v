// DRAM - Data RAM (8KB)

module dram (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] addr,
    input  wire        req,
    input  wire        we,
    input  wire [3:0]  be,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output reg         ready
);

    localparam RAM_SIZE = 8 * 1024;   // 8KB
    localparam ADDR_BITS = 13;        // 2^13 = 8192

    reg [31:0] ram [0:RAM_SIZE/4-1];

    wire [ADDR_BITS-1:2] word_addr = addr[ADDR_BITS-1:2];

    // Read with byte/half selection
    always @(*) begin
        rdata = ram[word_addr];
        case (be)
            4'b0001: begin  // Byte
                case (addr[1:0])
                    2'b00: rdata = {{24{ram[word_addr][7]}}, ram[word_addr][7:0]};
                    2'b01: rdata = {{24{ram[word_addr][15]}}, ram[word_addr][15:8]};
                    2'b10: rdata = {{24{ram[word_addr][23]}}, ram[word_addr][23:16]};
                    2'b11: rdata = {{24{ram[word_addr][31]}}, ram[word_addr][31:24]};
                endcase
            end
            4'b0010: begin
                case (addr[1:0])
                    2'b00: rdata = {{24{ram[word_addr][15]}}, ram[word_addr][15:8]};
                    2'b01: rdata = {{24{ram[word_addr][23]}}, ram[word_addr][23:16]};
                    2'b10: rdata = {{24{ram[word_addr][31]}}, ram[word_addr][31:24]};
                    default: rdata = 32'h0;
                endcase
            end
            4'b0100: begin
                case (addr[1:0])
                    2'b00: rdata = {{24{ram[word_addr][23]}}, ram[word_addr][23:16]};
                    2'b01: rdata = {{24{ram[word_addr][31]}}, ram[word_addr][31:24]};
                    default: rdata = 32'h0;
                endcase
            end
            4'b1000: rdata = {{24{ram[word_addr][31]}}, ram[word_addr][31:24]};
            4'b0011: begin  // Halfword
                case (addr[1])
                    1'b0: rdata = {{16{ram[word_addr][15]}}, ram[word_addr][15:0]};
                    1'b1: rdata = {{16{ram[word_addr][31]}}, ram[word_addr][31:16]};
                endcase
            end
            4'b1100: begin
                case (addr[1])
                    1'b0: rdata = {{16{ram[word_addr][15]}}, ram[word_addr][15:0]};
                    1'b1: rdata = {{16{ram[word_addr][31]}}, ram[word_addr][31:16]};
                endcase
            end
            4'b1111: rdata = ram[word_addr];
            default: rdata = ram[word_addr];
        endcase
        ready = req;
    end

    // Write
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < RAM_SIZE/4; i = i + 1) begin
                ram[i] <= 32'h0;
            end
        end else if (req && we) begin
            if (be[0]) ram[word_addr][7:0] <= wdata[7:0];
            if (be[1]) ram[word_addr][15:8] <= wdata[15:8];
            if (be[2]) ram[word_addr][23:16] <= wdata[23:16];
            if (be[3]) ram[word_addr][31:24] <= wdata[31:24];
        end
    end

endmodule
