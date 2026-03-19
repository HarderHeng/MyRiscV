`ifndef FLASH_CTRL_SV
`define FLASH_CTRL_SV

// ============================================================
//  FlashCtrl — 片上 Flash 控制器
//  地址空间：0x20000000 ~ 0x2012FFFF（76KB 用户区）
//
//  `ifdef SYNTHESIS：例化 Gowin FLASH608K 原语
//  `else            ：$readmemh 行为模型（仿真用）
//
//  读时序（2 状态机）：
//    S_IDLE → S_READ（建立 XADR/YADR，等待 1 周期）→
//    输出 cpu_rdata_vld=1，返回 S_IDLE
//
//  地址映射：
//    cpu_addr[16:2]  = word_addr（最大 32K 字 = 128KB，实际 76KB 可用）
//    XADR[8:0]       = word_addr[14:6]  （页地址）
//    YADR[5:0]       = word_addr[5:0]   （页内字偏移）
// ============================================================
module FlashCtrl (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] cpu_addr,      // CPU 数据总线地址
    input  wire        cpu_ren,       // 读使能（已由 sel_flash 选通）
    output reg  [31:0] cpu_rdata,     // 读数据
    output reg         cpu_rdata_vld  // 读数据有效（1 周期脉冲）
);

// 状态机
localparam S_IDLE = 1'b0;
localparam S_READ = 1'b1;

reg state;

// word 地址
wire [14:0] word_addr = cpu_addr[16:2];
wire [8:0]  xadr      = word_addr[14:6];
wire [5:0]  yadr      = word_addr[5:0];

`ifdef SYNTHESIS

// ============================================================
//  综合路径：例化 FLASH608K 原语
// ============================================================

wire [31:0] flash_dout;

FLASH608K u_flash (
    .XADR  (xadr),
    .YADR  (yadr),
    .XE    (1'b1),       // 片选使能（常使能）
    .YE    (1'b1),       // 列使能（常使能）
    .SE    (1'b1),       // 敏感放大器使能
    .ERASE (1'b0),       // 不擦除
    .PROG  (1'b0),       // 不编程
    .NVSTR (1'b0),
    .DIN   (32'h0),
    .DOUT  (flash_dout)
);

// 状态机：S_IDLE → S_READ → 输出有效 → S_IDLE
always @(posedge clk) begin
    if (rst) begin
        state        <= S_IDLE;
        cpu_rdata_vld<= 1'b0;
        cpu_rdata    <= 32'h0;
    end else begin
        cpu_rdata_vld <= 1'b0;
        case (state)
            S_IDLE: begin
                if (cpu_ren) begin
                    state <= S_READ;
                end
            end
            S_READ: begin
                // XADR/YADR 已在上周期建立（组合逻辑），
                // 此时 flash_dout 有效（异步读需建立时间 ≥1 周期）
                cpu_rdata     <= flash_dout;
                cpu_rdata_vld <= 1'b1;
                state         <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase
    end
end

`else

// ============================================================
//  仿真路径：$readmemh 行为模型
//  读 flash_init.mem（32K 字 × 32bit）
// ============================================================

reg [31:0] flash_mem [0:32767];

initial begin
    $readmemh("rtl/perips/flash_init.mem", flash_mem);
end

always @(posedge clk) begin
    if (rst) begin
        state        <= S_IDLE;
        cpu_rdata_vld<= 1'b0;
        cpu_rdata    <= 32'h0;
    end else begin
        cpu_rdata_vld <= 1'b0;
        case (state)
            S_IDLE: begin
                if (cpu_ren) begin
                    state <= S_READ;
                end
            end
            S_READ: begin
                cpu_rdata     <= flash_mem[word_addr];
                cpu_rdata_vld <= 1'b1;
                state         <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase
    end
end

`endif // SYNTHESIS

endmodule

`endif // FLASH_CTRL_SV
