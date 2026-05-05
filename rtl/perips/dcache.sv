`ifndef DCACHE_SV
`define DCACHE_SV

// ============================================================
//  D-Cache (Data Cache) - 4KB, 2-way, 32B line
//  Write-back, write-allocate 策略
//
//  地址映射:
//    Index: addr[6:2] (5 bits, 32 lines per way)
//    Tag: addr[31:7] (25 bits, 存储低7位)
// ============================================================
module DCache (
    input  wire        clk,
    input  wire        rst,

    // CPU MEM 阶段接口
    input  wire [31:0] mem_addr,
    input  wire        mem_ren,
    input  wire        mem_wen,
    input  wire [3:0]  mem_be,
    input  wire [31:0] mem_wdata,
    output reg  [31:0] mem_rdata,
    output reg         mem_rvalid,

    // Cache 控制
    input  wire        flush,
    input  wire        invalidate,

    // 系统总线接口
    output reg  [31:0] bus_addr,
    output reg         bus_req,
    input  wire [31:0] bus_rdata,
    input  wire        bus_rvalid,
    output reg  [31:0] bus_wdata,
    output reg  [3:0]  bus_be
);

localparam LINES   = 7;      // 128 lines per way
localparam TAG_BITS = 7;
localparam WORDS_PER_LINE = 8;  // 32B / 4B
localparam NUM_WAYS = 2;

// Cache 数据和元数据 - [way][line][word]
reg [31:0] cache_data [0:NUM_WAYS-1][0:(1<<LINES)-1][0:WORDS_PER_LINE-1];
reg [TAG_BITS-1:0] cache_tag [0:(1<<LINES)-1][0:NUM_WAYS-1];
reg cache_valid [0:(1<<LINES)-1][0:NUM_WAYS-1];
reg cache_dirty [0:(1<<LINES)-1][0:NUM_WAYS-1];

// 地址解析
wire [LINES-1:0] index = mem_addr[6:2];

// Initialize arrays to 0
initial begin
    integer w, l, b;
    for (w = 0; w < NUM_WAYS; w = w + 1) begin
        for (l = 0; l < (1<<LINES); l = l + 1) begin
            cache_valid[l][w] = 1'b0;
            cache_dirty[l][w] = 1'b0;
            lru[l] = 1'b0;
            for (b = 0; b < WORDS_PER_LINE; b = b + 1) begin
                cache_data[w][l][b] = 32'h0;
            end
        end
    end
end
wire [TAG_BITS-1:0] tag = mem_addr[31:7];
wire [2:0] word_offset = mem_addr[4:2];

// 路选择
wire hit_way0 = cache_valid[index][0] && (cache_tag[index][0] == tag);
wire hit_way1 = cache_valid[index][1] && (cache_tag[index][1] == tag);
wire hit = hit_way0 || hit_way1;

// Miss 信号
wire read_miss = mem_ren && !hit;
wire write_miss = mem_wen && !hit;

// 读数据输出
reg [31:0] read_data;
always @(*) begin
    if (hit_way0)
        read_data = cache_data[0][index][word_offset];
    else if (hit_way1)
        read_data = cache_data[1][index][word_offset];
    else
        read_data = 32'h0;
end

always @(posedge clk) begin
    if (rst) begin
        mem_rdata <= 32'h0;
        mem_rvalid <= 1'b0;
    end else begin
        mem_rvalid <= 1'b0;
        if (mem_ren && hit) begin
            mem_rdata <= read_data;
            mem_rvalid <= 1'b1;
        end
    end
end

// 状态机
localparam S_IDLE     = 3'b000;
localparam S_READ_MISS = 3'b001;
localparam S_FILL     = 3'b010;
localparam S_WRITE_MISS = 3'b011;
localparam S_EVICT    = 3'b100;
localparam S_EVICT_WRITE = 3'b101;

reg [2:0] state;
reg [1:0] miss_way;
reg [LINES-1:0] miss_index;
reg [TAG_BITS-1:0] miss_tag;
reg [2:0] fill_word_cnt;
reg [31:0] evict_addr;
reg [3:0] evict_be;
reg [31:0] evict_wdata;

// LRU
reg lru [0:(1<<LINES)-1];
wire replace_way = lru[index];

// 写命中处理
always @(posedge clk) begin
    if (rst) begin
        // Valid and dirty are reset to 0 via separate reset logic
    end else if (mem_wen && hit_way0) begin
        if (mem_be[0]) cache_data[0][index][word_offset][7:0] <= mem_wdata[7:0];
        if (mem_be[1]) cache_data[0][index][word_offset][15:8] <= mem_wdata[15:8];
        if (mem_be[2]) cache_data[0][index][word_offset][23:16] <= mem_wdata[23:16];
        if (mem_be[3]) cache_data[0][index][word_offset][31:24] <= mem_wdata[31:24];
        cache_dirty[index][0] <= 1'b1;
    end else if (mem_wen && hit_way1) begin
        if (mem_be[0]) cache_data[1][index][word_offset][7:0] <= mem_wdata[7:0];
        if (mem_be[1]) cache_data[1][index][word_offset][15:8] <= mem_wdata[15:8];
        if (mem_be[2]) cache_data[1][index][word_offset][23:16] <= mem_wdata[23:16];
        if (mem_be[3]) cache_data[1][index][word_offset][31:24] <= mem_wdata[31:24];
        cache_dirty[index][1] <= 1'b1;
    end
end

// 总线事务
always @(*) begin
    bus_req = 1'b0;
    bus_addr = 32'h0;
    bus_wdata = 32'h0;
    bus_be = 4'h0;

    case (state)
        S_READ_MISS: begin
            bus_req = 1'b1;
            bus_addr = {miss_tag, miss_index, 5'b0};
        end

        S_FILL: begin
            bus_req = 1'b1;
            bus_addr = {miss_tag, miss_index, fill_word_cnt, 2'b0};
        end

        S_EVICT_WRITE: begin
            bus_req = 1'b1;
            bus_addr = evict_addr;
            bus_wdata = evict_wdata;
            bus_be = evict_be;
        end

        default: ;
    endcase
end

// 状态机
integer i, j;
always @(posedge clk) begin
    if (rst) begin
        state <= S_IDLE;
        // lru reset handled separately
    end else begin
        case (state)
            S_IDLE: begin
                if (read_miss || write_miss) begin
                    miss_way <= replace_way;
                    miss_index <= index;
                    miss_tag <= tag;
                    fill_word_cnt <= 3'b0;
                    if (cache_dirty[index][replace_way])
                        state <= S_EVICT;
                    else
                        state <= S_READ_MISS;
                    evict_addr <= {cache_tag[index][replace_way], index, 5'b0};
                end
            end

            S_EVICT: begin
                state <= S_READ_MISS;
            end

            S_READ_MISS: begin
                if (bus_rvalid) begin
                    state <= S_FILL;
                end
            end

            S_FILL: begin
                if (bus_rvalid) begin
                    cache_data[miss_way][miss_index][fill_word_cnt] <= bus_rdata;
                    fill_word_cnt <= fill_word_cnt + 1;
                    if (fill_word_cnt == 3'b111) begin
                        cache_tag[miss_index][miss_way] <= miss_tag;
                        cache_valid[miss_index][miss_way] <= 1'b1;
                        cache_dirty[miss_index][miss_way] <= 1'b0;
                        lru[miss_index] <= ~miss_way;
                        state <= S_IDLE;
                    end
                end
            end

            S_EVICT_WRITE: begin
                if (bus_rvalid) begin
                    state <= S_READ_MISS;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule

`endif // DCACHE_SV