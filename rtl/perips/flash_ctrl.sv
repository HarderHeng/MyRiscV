`ifndef FLASH_CTRL_SV
`define FLASH_CTRL_SV

// ============================================================
//  FlashCtrl — 片上 Flash 控制器
//  地址空间：0x20000000 ~ 0x2012FFFF（76KB 用户区）
//
//  `ifdef SYNTHESIS：例化 Gowin FLASH608K 原语
//  `else            ：$readmemh 行为模型（仿真用）
//
//  读时序（2 周期延迟）：
//    T0: S_IDLE → S_READ（锁存地址）
//    T1: S_READ → 输出数据，cpu_rdata_vld/irdata_vld=1
//
//  地址映射：
//    cpu_addr[16:2]  = word_addr（最大 32K 字 = 128KB，实际 76KB 可用）
//    XADR[8:0]       = word_addr[14:6]  （页地址）
//    YADR[5:0]       = word_addr[5:0]   （页内字偏移）
// ============================================================
module FlashCtrl (
    input  wire        clk,
    input  wire        rst,

    // CPU 数据总线接口
    input  wire [31:0] cpu_addr,
    input  wire        cpu_ren,
    output reg  [31:0] cpu_rdata,
    output reg         cpu_rdata_vld,

    // CPU 指令总线接口（XIP：Execute In Place）
    input  wire [31:0] iaddr,
    input  wire        iren,
    output reg  [31:0] irdata,
    output reg         irdata_vld
);

// 状态机
localparam S_IDLE = 1'b0;
localparam S_READ = 1'b1;

reg state;
reg state_ir;  // 指令读状态机

// word 地址（数据总线）
wire [14:0] word_addr = cpu_addr[16:2];
wire [8:0]  xadr      = word_addr[14:6];
wire [5:0]  yadr      = word_addr[5:0];

// word 地址（指令总线）
wire [14:0] iword_addr = iaddr[16:2];
wire [8:0]  i_xadr     = iword_addr[14:6];
wire [5:0]  i_yadr     = iword_addr[5:0];

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

// 数据总线读状态机：S_IDLE → S_READ → 输出有效
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
                cpu_rdata     <= flash_dout;
                cpu_rdata_vld <= 1'b1;
                state         <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase
    end
end

// 指令总线读状态机：独立于数据总线
// Flash 宏是异步输出，地址建立后数据即有效
always @(posedge clk) begin
    if (rst) begin
        state_ir    <= S_IDLE;
        irdata_vld  <= 1'b0;
        irdata      <= 32'h0;
    end else begin
        irdata_vld <= 1'b0;
        case (state_ir)
            S_IDLE: begin
                if (iren) begin
                    state_ir <= S_READ;
                end
            end
            S_READ: begin
                // Flash 宏输出在地址建立后有效
                // 此处需要确保时序满足 27 MHz
                irdata     <= flash_dout;
                irdata_vld <= 1'b1;
                state_ir   <= S_IDLE;
            end
            default: state_ir <= S_IDLE;
        endcase
    end
end

`else

// ============================================================
//  仿真路径：$readmemh 行为模型
//  读 flash_init.mem（32K 字 × 32bit）
//  组合读：地址有效时数据立即可用（用于 XIP 和数据读）
// ============================================================

// 指令总线读（XIP，组合逻辑）
reg [31:0] flash_mem [0:32767];

wire [31:0] irdata_comb = flash_mem[iword_addr];

assign irdata = iren ? irdata_comb : 32'h0;
assign irdata_vld = iren;

// 数据总线读（组合逻辑，与指令读一致）
assign cpu_rdata = flash_mem[word_addr];
assign cpu_rdata_vld = cpu_ren;

initial begin
    $readmemh("rtl/perips/flash_init.mem", flash_mem);
    $display("[FlashCtrl] Loaded flash_init.mem, first 5 words:");
    $display("  0x00: %h", flash_mem[0]);
    $display("  0x04: %h", flash_mem[1]);
    $display("  0x08: %h", flash_mem[2]);
    $display("  0x0C: %h", flash_mem[3]);
    $display("  0x10: %h", flash_mem[4]);
end

`endif // SYNTHESIS

endmodule

`endif // FLASH_CTRL_SV
