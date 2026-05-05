`ifndef AHBLITE_DCACHE_SV
`define AHBLITE_DCACHE_SV

// ============================================================
//  AHB-Lite D-Cache - 2KB Direct-Mapped Write-Back Data Cache
//
//  规格:
//    - 大小: 2KB
//    - 结构: 直接映射
//    - 行大小: 16B (4 words)
//    - 行数: 128
//    - 标签: addr[31:7] (存高8位)
//    - 写策略: 写回, 写分配
//    - 替换策略: 直接映射无替换
//
//  AHB-Lite 从设备接口
// ============================================================
module AHB_Lite_DCache (
    input  wire        clk,
    input  wire        rst,

    // AHB-Lite Slave Interface (来自 CPU)
    input  wire [31:0] haddr,
    input  wire        hsel,
    input  wire        hready_in,
    input  wire [1:0]  htrans,
    input  wire        hwrite,
    input  wire [2:0]  hsize,
    input  wire [3:0]  hstrb,
    input  wire [31:0] hwdata,
    output wire [31:0] hrdata,
    output wire        hreadyout,
    output wire        hresp,

    // AHB-Lite Master Interface (向内存/Flash 的请求)
    output wire [31:0] m_haddr,
    output wire        m_hsel,
    output wire        m_hready_in,
    output wire [1:0]  m_htrans,
    output wire        m_hwrite,
    output wire [2:0]  m_hsize,
    output wire [3:0]  m_hstrb,
    output wire [31:0] m_hwdata,
    input  wire [31:0] m_hrdata,
    input  wire        m_hreadyout,
    input  wire        m_hresp
);

    // ============================================================
    //  参数
    // ============================================================
    localparam LINE_SIZE = 16;           // 每行 16 字节
    localparam LINE_WORDS = LINE_SIZE / 4; // 4 words
    localparam NUM_LINES = 128;           // 128 行 (2KB / 16B)
    localparam TAG_BITS = 8;              // 存储高 8 位 tag

    // Cache 地址解析
    wire [6:0] req_line_idx = haddr[6:2];  // Line index
    wire [1:0] word_off = haddr[3:2];     // Word offset within line
    wire [TAG_BITS-1:0] req_tag = haddr[31:24];  // 高 8 位

    // ============================================================
    //  状态机
    // ============================================================
    localparam S_IDLE         = 4'b0000;
    localparam S_READ_HIT     = 4'b0001;
    localparam S_WRITE_HIT    = 4'b0010;
    localparam S_READ_MISS    = 4'b0100;
    localparam S_WRITE_MISS   = 4'b0101;
    localparam S_FILL         = 4'b0110;
    localparam S_EVICT        = 4'b0111;
    localparam S_EVICT_WRITE  = 4'b1000;

    reg [3:0] state;
    reg [3:0] next_state;

    // Cache 存储
    reg [TAG_BITS-1:0] tag_r [0:NUM_LINES-1];
    reg                 valid_r [0:NUM_LINES-1];
    reg                 dirty_r [0:NUM_LINES-1];
    reg [31:0]          data_r [0:NUM_LINES-1][0:LINE_WORDS-1];

    // 当前访问
    reg [6:0] acc_line_idx;
    reg [1:0] acc_word_off;
    reg acc_we;
    reg [3:0] acc_be;
    reg [31:0] acc_wdata;

    // 填充缓冲
    reg [31:0] fill_data [0:LINE_WORDS-1];
    reg [6:0] fill_line_idx;

    // 驱逐相关
    reg [6:0] evict_line_idx;
    reg [TAG_BITS-1:0] evict_tag;

    // ============================================================
    //  Cache 查找
    // ============================================================
    wire cache_valid = valid_r[req_line_idx];
    wire [TAG_BITS-1:0] cache_tag = tag_r[req_line_idx];
    wire tag_match = cache_valid && (cache_tag == req_tag);

    // ============================================================
    //  状态机转换
    // ============================================================
    wire h_req = hsel && htrans[1] && hready_in;

    always @(*) begin
        case (state)
            S_IDLE: begin
                if (h_req) begin
                    if (tag_match) begin
                        next_state = hwrite ? S_WRITE_HIT : S_READ_HIT;
                    end else begin
                        if (dirty_r[req_line_idx]) begin
                            next_state = S_EVICT;
                        end else begin
                            next_state = hwrite ? S_WRITE_MISS : S_READ_MISS;
                        end
                    end
                end else begin
                    next_state = S_IDLE;
                end
            end

            S_READ_HIT:  next_state = S_IDLE;
            S_WRITE_HIT: next_state = S_IDLE;

            S_READ_MISS, S_WRITE_MISS: next_state = S_FILL;

            S_FILL: begin
                if (m_hreadyout) begin
                    if (state == S_WRITE_MISS) begin
                        next_state = S_WRITE_HIT;
                    end else begin
                        next_state = S_READ_HIT;
                    end
                end else begin
                    next_state = S_FILL;
                end
            end

            S_EVICT: next_state = S_EVICT_WRITE;
            S_EVICT_WRITE: next_state = m_hreadyout ? S_READ_MISS : S_EVICT_WRITE;

            default: next_state = S_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // ============================================================
    //  访问记录
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            acc_line_idx <= 7'b0;
            acc_word_off <= 2'b0;
            acc_we <= 1'b0;
            acc_be <= 4'h0;
            acc_wdata <= 32'h0;
        end else if (state == S_IDLE && h_req) begin
            acc_line_idx <= req_line_idx;
            acc_word_off <= word_off;
            acc_we <= hwrite;
            acc_be <= hstrb;
            acc_wdata <= hwdata;
        end
    end

    // ============================================================
    //  驱逐缓冲更新
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            evict_line_idx <= 7'b0;
            evict_tag <= 8'h0;
        end else if (state == S_IDLE && h_req && !tag_match && dirty_r[req_line_idx]) begin
            evict_line_idx <= req_line_idx;
            evict_tag <= tag_r[req_line_idx];
        end
    end

    // ============================================================
    //  填充缓冲更新
    // ============================================================
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            fill_line_idx <= 7'b0;
        end else if (state == S_FILL && m_hreadyout) begin
            fill_data[0] <= m_hrdata;
            fill_data[1] <= m_hrdata;  // 简化：实际需要突发
            fill_data[2] <= m_hrdata;
            fill_data[3] <= m_hrdata;
            fill_line_idx <= acc_line_idx;
        end
    end

    // ============================================================
    //  Cache 行更新
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid_r[i] <= 1'b0;
                dirty_r[i] <= 1'b0;
                tag_r[i] <= 8'h0;
            end
        end else if (state == S_FILL && m_hreadyout) begin
            valid_r[fill_line_idx] <= 1'b1;
            dirty_r[fill_line_idx] <= 1'b0;
            tag_r[fill_line_idx] <= req_tag;
            data_r[fill_line_idx][0] <= fill_data[0];
            data_r[fill_line_idx][1] <= fill_data[1];
            data_r[fill_line_idx][2] <= fill_data[2];
            data_r[fill_line_idx][3] <= fill_data[3];
        end else if (state == S_WRITE_HIT) begin
            // 在命中时直接更新
            dirty_r[acc_line_idx] <= 1'b1;
            case (acc_word_off)
                2'b00: data_r[acc_line_idx][0] <= acc_wdata;
                2'b01: data_r[acc_line_idx][1] <= acc_wdata;
                2'b10: data_r[acc_line_idx][2] <= acc_wdata;
                2'b11: data_r[acc_line_idx][3] <= acc_wdata;
            endcase
        end
    end

    // ============================================================
    //  读数据选择
    // ============================================================
    reg [31:0] hit_data;
    always @(*) begin
        case (acc_word_off)
            2'b00: hit_data = data_r[acc_line_idx][0];
            2'b01: hit_data = data_r[acc_line_idx][1];
            2'b10: hit_data = data_r[acc_line_idx][2];
            2'b11: hit_data = data_r[acc_line_idx][3];
        endcase
    end

    assign hrdata = (state == S_READ_HIT) ? hit_data : 32'h0;

    // ============================================================
    //  上游就绪信号
    // ============================================================
    assign hreadyout = (state == S_READ_HIT || state == S_WRITE_HIT) ? 1'b1 :
                       (state == S_IDLE) ? 1'b1 : 1'b0;
    assign hresp = 1'b0;  // OK

    // ============================================================
    //  下游请求生成
    // ============================================================
    wire [31:0] fill_addr = {req_tag, acc_line_idx, 5'b0};
    wire [31:0] evict_addr = {evict_tag, evict_line_idx, 5'b0};

    assign m_haddr = (state == S_FILL) ? fill_addr :
                      (state == S_EVICT_WRITE) ? evict_addr : 32'h0;
    assign m_hsel = (state == S_FILL || state == S_EVICT_WRITE);
    assign m_hready_in = m_hreadyout;
    assign m_htrans = (state == S_FILL || state == S_EVICT_WRITE) ? 2'b10 : 2'b00;
    assign m_hwrite = (state == S_EVICT_WRITE);
    assign m_hsize = 3'b010;
    assign m_hstrb = (state == S_EVICT_WRITE) ? 4'hF : 4'h0;
    assign m_hwdata = (state == S_EVICT_WRITE) ? data_r[evict_line_idx][0] : 32'h0; // 简化

endmodule

`endif // AHBLITE_DCACHE_SV
