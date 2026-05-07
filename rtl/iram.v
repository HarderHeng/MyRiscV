// IRAM - Instruction RAM (16KB)
// Dual-port RAM with initialized contents

module iram (
    input  wire        clk,
    // I-port (read-only, instruction fetch)
    input  wire [31:0] i_addr,
    input  wire        i_req,
    output reg  [31:0] i_rdata,
    output reg         i_ready,
    // D-port (read/write, data access)
    input  wire [31:0] d_addr,
    input  wire        d_req,
    input  wire        d_we,
    input  wire [3:0]  d_be,
    input  wire [31:0] d_wdata,
    output reg  [31:0] d_rdata,
    output reg         d_ready
);

    localparam RAM_SIZE = 16 * 1024;  // 16KB
    localparam ADDR_BITS = 14;        // 2^14 = 16384

    reg [31:0] ram [0:RAM_SIZE/4-1];

    // Word-aligned addresses
    wire [ADDR_BITS-1:2] i_word_addr = i_addr[ADDR_BITS-1:2];
    wire [ADDR_BITS-1:2] d_word_addr = d_addr[ADDR_BITS-1:2];

    // I-port read (combinational)
    always @(*) begin
        i_rdata = ram[i_word_addr];
        i_ready = i_req;
    end

    // D-port read with byte/half selection
    always @(*) begin
        d_rdata = ram[d_word_addr];
        case (d_be)
            4'b0001: begin  // Byte
                case (d_addr[1:0])
                    2'b00: d_rdata = {24'b0, ram[d_word_addr][7:0]};
                    2'b01: d_rdata = {24'b0, ram[d_word_addr][15:8]};
                    2'b10: d_rdata = {24'b0, ram[d_word_addr][23:16]};
                    2'b11: d_rdata = {24'b0, ram[d_word_addr][31:24]};
                endcase
            end
            4'b0010: begin
                case (d_addr[1:0])
                    2'b00: d_rdata = {24'b0, ram[d_word_addr][15:8]};
                    2'b01: d_rdata = {24'b0, ram[d_word_addr][23:16]};
                    2'b10: d_rdata = {24'b0, ram[d_word_addr][31:24]};
                    default: d_rdata = 32'h0;
                endcase
            end
            4'b0100: begin
                case (d_addr[1:0])
                    2'b00: d_rdata = {24'b0, ram[d_word_addr][23:16]};
                    2'b01: d_rdata = {24'b0, ram[d_word_addr][31:24]};
                    default: d_rdata = 32'h0;
                endcase
            end
            4'b1000: d_rdata = {24'b0, ram[d_word_addr][31:24]};
            4'b0011: begin  // Halfword
                case (d_addr[1])
                    1'b0: d_rdata = {16'b0, ram[d_word_addr][15:0]};
                    1'b1: d_rdata = {16'b0, ram[d_word_addr][31:16]};
                endcase
            end
            4'b1100: begin
                case (d_addr[1])
                    1'b0: d_rdata = {16'b0, ram[d_word_addr][15:0]};
                    1'b1: d_rdata = {16'b0, ram[d_word_addr][31:16]};
                endcase
            end
            4'b1111: d_rdata = ram[d_word_addr];
            default: d_rdata = ram[d_word_addr];
        endcase
        d_ready = d_req;
    end

    // D-port write
    always @(posedge clk) begin
        if (d_req && d_we) begin
            if (d_be[0]) ram[d_word_addr][7:0] <= d_wdata[7:0];
            if (d_be[1]) ram[d_word_addr][15:8] <= d_wdata[15:8];
            if (d_be[2]) ram[d_word_addr][23:16] <= d_wdata[23:16];
            if (d_be[3]) ram[d_word_addr][31:24] <= d_wdata[31:24];
        end
    end

    // Initialize with program from hex file
    initial begin
        $readmemh("iram_init.hex", ram);
    end

endmodule
