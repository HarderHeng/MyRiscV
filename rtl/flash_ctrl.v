// Flash Controller (XIP - Execute In Place)
// 76KB Flash at 0x20000000

module flash_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] addr,
    input  wire        req,
    output reg  [31:0] rdata,
    output reg         ready
);

    localparam FLASH_SIZE = 76 * 1024;  // 76KB
    localparam ADDR_BITS = 17;          // 2^17 = 131072

    reg [31:0] flash_mem [0:FLASH_SIZE/4-1];

    wire [ADDR_BITS-1:2] word_addr = addr[ADDR_BITS-1:2];

    // Read (combinational for XIP)
    always @(*) begin
        rdata = flash_mem[word_addr];
        ready = req;
    end

    // Default flash contents - simple boot
    integer i;
    initial begin
        for (i = 0; i < FLASH_SIZE/4; i = i + 1) begin
            flash_mem[i] = 32'h00000013;  // NOP
        end
        // Boot: jump to self at flash base
        flash_mem[0] = 32'h0000006f;  // j 0x20000000
    end

endmodule
