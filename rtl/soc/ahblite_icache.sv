`ifndef AHBLITE_ICACHE_SV
`define AHBLITE_ICACHE_SV

// ============================================================
//  AHB-Lite I-Cache - 2KB Direct-Mapped Instruction Cache
//
//  规格:
//    - 大小: 2KB
//    - 结构: 直接映射
//    - 行大小: 16B (4 words)
//    - 行数: 128
//    - 标签: addr[31:7] (存高8位)
//    - 替换策略: 直接映射无替换
//
//  AHB-Lite 从设备接口
// ============================================================
module AHB_Lite_ICache (
    input  wire        clk,
    input  wire        rst,

    // AHB-Lite Slave Interface (来自 CPU/上层的请求)
    input  wire [31:0] haddr,         // 地址
    input  wire        hsel,           // 选择
    input  wire        hready_in,      // 主设备就绪
    input  wire [1:0]  htrans,        // 传输类型
    input  wire        hwrite,         // 写使能 (无效)
    input  wire [2:0]  hsize,         // 数据大小
    input  wire [3:0]  hstrb,         // 字节使能
    input  wire [31:0] hwdata,        // 写数据
    output wire [31:0] hrdata,         // 读数据
    output wire        hreadyout,      // 传输完成
    output wire        hresp,          // 响应

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
    localparam IDX_BITS = $clog2(NUM_LINES); // 7 bits
    localparam TAG_BITS = 8;              // 存储高 8 位 tag

    // Cache 地址解析
    // addr[6:2] = line index (5 bits for 128 lines)
    // addr[6:2] = offset in line (5 bits, but we need addr[4:2] for word offset within line)
    // addr[6:5] = which word within line (2 bits)
    // addr[4:2] = byte offset within word (3 bits, but we read full word)
    wire [6:0] line_idx = haddr[6:0];  // Actually only need [6:2] for line
    wire [1:0] word_off = haddr[3:2];   // Word offset within line

    // ============================================================
    //  状态机
    // ============================================================
    localparam S_IDLE  = 2'b00;
    localparam S_HIT   = 2'b01;
    localparam S_FILL  = 2'b10;

    reg [1:0] state;
    reg [1:0] next_state;

    // Cache 存储
    reg [TAG_BITS-1:0] tag_r [0:NUM_LINES-1];  // Tag 存储
    reg                 valid_r [0:NUM_LINES-1]; // Valid bit
    reg [31:0]          data_r [0:NUM_LINES-1][0:LINE_WORDS-1]; // 4 words per line

    // 当前访问
    reg [6:0] acc_line_idx;
    reg [1:0] acc_word_off;

    // 填充缓冲
    reg [31:0] fill_data [0:LINE_WORDS-1];
    reg [6:0] fill_line_idx;

    // ============================================================
    //  地址解析
    // ============================================================
    wire [6:0] req_line_idx = haddr[6:2];  // Line index (5 bits)
    wire [TAG_BITS-1:0] req_tag = haddr[31:24];  // 高 8 位

    // ============================================================
    //  Cache 查找
    // ============================================================
    wire cache_valid = valid_r[req_line_idx];
    wire [TAG_BITS-1:0] cache_tag = tag_r[req_line_idx];
    wire tag_match = cache_valid && (cache_tag == req_tag);

    // ============================================================
    //  状态机转换
    // ============================================================
    always @(*) begin
        case (state)
            S_IDLE:  next_state = (hsel && htrans[1]) ? (tag_match ? S_HIT : S_FILL) : S_IDLE;
            S_HIT:   next_state = S_IDLE;
            S_FILL:  next_state = (m_hreadyout) ? S_HIT : S_FILL;
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
        end else if (state == S_IDLE && hsel && htrans[1]) begin
            acc_line_idx <= req_line_idx;
            acc_word_off <= haddr[3:2];
        end
    end

    // ============================================================
    //  填充缓冲更新
    // ============================================================
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < LINE_WORDS; i = i + 1) begin
                fill_data[i] <= 32'h0;
            end
            fill_line_idx <= 7'b0;
        end else if (state == S_FILL && m_hreadyout) begin
            // 从下游读取 4 个 word
            fill_data[0] <= m_hrdata;
            fill_data[1] <= m_hrdata;  // 简化：实际需要突发读取
            fill_data[2] <= m_hrdata;
            fill_data[3] <= m_hrdata;
            fill_line_idx <= acc_line_idx;
        end
    end

    // ============================================================
    //  Cache 行更新 (填充完成后)
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid_r[i] <= 1'b0;
                tag_r[i] <= 8'h0;
            end
        end else if (state == S_FILL && m_hreadyout) begin
            // 写入新行
            valid_r[fill_line_idx] <= 1'b1;
            tag_r[fill_line_idx] <= req_tag;
            data_r[fill_line_idx][0] <= fill_data[0];
            data_r[fill_line_idx][1] <= fill_data[1];
            data_r[fill_line_idx][2] <= fill_data[2];
            data_r[fill_line_idx][3] <= fill_data[3];
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

    assign hrdata = (state == S_HIT) ? hit_data : 32'h0;

    // ============================================================
    //  上游就绪信号
    // ============================================================
    assign hreadyout = (state == S_HIT) || (state == S_IDLE);
    assign hresp = 1'b0;  // OK

    // ============================================================
    //  下游请求生成
    // ============================================================
    wire [31:0] fill_addr = {req_tag, acc_line_idx, 5'b0};  // 行起始地址

    assign m_haddr = (state == S_FILL) ? fill_addr : 32'h0;
    assign m_hsel = (state == S_FILL);
    assign m_hready_in = m_hreadyout;
    assign m_htrans = (state == S_FILL) ? 2'b10 : 2'b00;  // NONSEQ
    assign m_hwrite = 1'b0;  // 始终读
    assign m_hsize = 3'b010; // 32-bit
    assign m_hstrb = 4'hF;   // 全字
    assign m_hwdata = 32'h0;

endmodule

`endif // AHBLITE_ICACHE_SV
