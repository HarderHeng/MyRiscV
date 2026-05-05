`ifndef ICACHE_SV
`define ICACHE_SV

// ============================================================
//  I-Cache (Instruction Cache) - 4KB, 2-way, 32B line
//  地址映射:
//    Index: addr[6:2] (5 bits, 32 lines per way)
//    Tag: addr[31:7] (25 bits, 存储低7位)
// ============================================================
module ICache (
    input  wire        clk,
    input  wire        rst,

    // CPU IF 阶段接口
    input  wire [31:0] if_addr,     // 取指地址
    input  wire        if_req,       // 取指请求
    output reg  [31:0] if_rdata,    // 指令数据
    output wire        if_rvalid,    // 数据有效
    output wire        if_miss,      // Cache miss

    // 系统总线接口 (填充 cache line)
    input  wire [31:0] bus_rdata,
    input  wire        bus_rvalid,
    output reg  [31:0] bus_addr,
    output reg         bus_req
);

localparam LINES      = 7;      // 128 lines per way
localparam WORDS_PER_LINE = 8;  // 32B / 4B
localparam NUM_WAYS   = 2;
localparam TAG_BITS   = 7;      // addr[31:7]

// Cache 结构 - [way][line][word]
reg [31:0] cache_data [0:NUM_WAYS-1][0:(1<<LINES)-1][0:WORDS_PER_LINE-1];
reg [TAG_BITS-1:0] cache_tag [0:(1<<LINES)-1][0:NUM_WAYS-1];
reg cache_valid [0:(1<<LINES)-1][0:NUM_WAYS-1];

// 初始化
integer w, l, b;
initial begin
    for (w = 0; w < NUM_WAYS; w = w + 1) begin
        for (l = 0; l < (1<<LINES); l = l + 1) begin
            cache_valid[l][w] = 1'b0;
            for (b = 0; b < WORDS_PER_LINE; b = b + 1) begin
                cache_data[w][l][b] = 32'h0;
            end
        end
    end
end

// 地址解析
wire [LINES-1:0] index = if_addr[6:2];
wire [TAG_BITS-1:0] tag = if_addr[31:7];
wire [2:0] word_offset = if_addr[4:2];

// 选择路
wire way_hit0 = cache_valid[index][0] && (cache_tag[index][0] == tag);
wire way_hit1 = cache_valid[index][1] && (cache_tag[index][1] == tag);
wire hit = way_hit0 || way_hit1;

assign if_miss = if_req && !hit;

// 输出数据选择
reg [31:0] hit_data;
always @(*) begin
    if (way_hit0)
        hit_data = cache_data[0][index][word_offset];
    else if (way_hit1)
        hit_data = cache_data[1][index][word_offset];
    else
        hit_data = 32'h0;
end

always @(posedge clk) begin
    if (rst) begin
        if_rdata <= 32'h0;
    end else begin
        if_rdata <= hit_data;
    end
end

assign if_rvalid = (state == S_IDLE) && hit;

// 状态机
localparam S_IDLE = 2'b00;
localparam S_FILL = 2'b01;

reg [1:0] state;
reg [1:0] refill_way;
reg [LINES-1:0] refill_index;
reg [2:0] refill_word_cnt;
reg [TAG_BITS-1:0] refill_tag;

// LRU 替换
reg lru [0:(1<<LINES)-1];
wire replace_way = lru[index];

// 总线请求
always @(*) begin
    if (state == S_IDLE && if_req && !hit) begin
        bus_req = 1'b1;
        bus_addr = {tag, index, 5'b0};
    end else begin
        bus_req = 1'b0;
        bus_addr = 32'h0;
    end
end

// 状态机
always @(posedge clk) begin
    if (rst) begin
        state <= S_IDLE;
        lru <= '{default: 0};
    end else begin
        case (state)
            S_IDLE: begin
                if (if_req && !hit) begin
                    state <= S_FILL;
                    refill_way <= replace_way;
                    refill_index <= index;
                    refill_tag <= tag;
                    refill_word_cnt <= 3'b0;
                end
            end

            S_FILL: begin
                if (bus_rvalid) begin
                    cache_data[refill_way][refill_index][refill_word_cnt] <= bus_rdata;
                    refill_word_cnt <= refill_word_cnt + 3'b1;

                    if (refill_word_cnt == 3'b111) begin
                        cache_tag[refill_index][refill_way] <= refill_tag;
                        cache_valid[refill_index][refill_way] <= 1'b1;
                        lru[refill_index] <= ~replace_way;
                        state <= S_IDLE;
                    end
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule

`endif // ICACHE_SV