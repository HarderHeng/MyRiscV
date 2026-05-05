`ifndef FLASH_CTRL_SV
`define FLASH_CTRL_SV
`timescale 1ns/1ps

// ============================================================
//  FlashCtrl — 片上 Flash 控制器
//  地址空间：0x20000000 ~ 0x2012FFFF（76KB）
//
//  地址映射：
//    addr[16:2] = word地址（最大32K字=128KB）
//    XADR[8:0] = word_addr[14:6]（页地址）
//    YADR[5:0] = word_addr[5:0]（页内字偏移）
//
//  对于仿真：假设Flash被映射到地址0
//  即 addr = 0x20000000 -> flash_mem[0]
// ============================================================
module FlashCtrl (
    input  wire        clk,
    input  wire        rst,

    // CPU 数据总线接口
    input  wire [31:0] cpu_addr,
    input  wire        cpu_ren,
    output reg  [31:0] cpu_rdata,
    output reg         cpu_rdata_vld,

    // CPU 指令总线接口（XIP）
    input  wire [31:0] iaddr,
    input  wire        iren,
    output reg  [31:0] irdata,
    output reg         irdata_vld
);

localparam S_IDLE = 1'b0;
localparam S_READ = 1'b1;

reg state;
reg state_ir;

// word地址计算
wire [14:0] word_addr = cpu_addr[16:2];
wire [8:0]  xadr = word_addr[14:6];
wire [5:0]  yadr = word_addr[5:0];

wire [14:0] iword_addr = iaddr[16:2];
wire [8:0]  i_xadr = iword_addr[14:6];
wire [5:0]  i_yadr = iword_addr[5:0];

`ifdef SYNTHESIS

// ============================================================
//  综合路径：例化 FLASH608K 原语
// ============================================================
wire [31:0] flash_dout;

FLASH608K u_flash (
    .XADR  (xadr),
    .YADR  (yadr),
    .XE    (1'b1),
    .YE    (1'b1),
    .SE    (1'b1),
    .ERASE (1'b0),
    .PROG  (1'b0),
    .NVSTR (1'b0),
    .DIN   (32'h0),
    .DOUT  (flash_dout)
);

always @(posedge clk) begin
    if (rst) begin
        state <= S_IDLE;
        cpu_rdata_vld <= 1'b0;
        cpu_rdata <= 32'h0;
    end else begin
        cpu_rdata_vld <= 1'b0;
        case (state)
            S_IDLE: if (cpu_ren) state <= S_READ;
            S_READ: begin
                cpu_rdata <= flash_dout;
                cpu_rdata_vld <= 1'b1;
                state <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase
    end
end

always @(posedge clk) begin
    if (rst) begin
        state_ir <= S_IDLE;
        irdata_vld <= 1'b0;
        irdata <= 32'h0;
    end else begin
        irdata_vld <= 1'b0;
        case (state_ir)
            S_IDLE: if (iren) state_ir <= S_READ;
            S_READ: begin
                irdata <= flash_dout;
                irdata_vld <= 1'b1;
                state_ir <= S_IDLE;
            end
            default: state_ir <= S_IDLE;
        endcase
    end
end

`else

// ============================================================
//  仿真路径：$readmemh 行为模型
//  Flash 基地址: 0x20000000
//  地址映射: addr = 0x20000000 -> flash_mem[0]
// ============================================================
reg [31:0] flash_mem [0:32767];

localparam FLASH_BASE = 32'h2000_0000;

// 指令读（XIP，组合逻辑）
// 计算相对于 Flash 基地址的字偏移
wire [31:0] flash_offset = iaddr - FLASH_BASE;
wire [14:0] flash_idx = flash_offset[16:2];
assign irdata = (iren && flash_idx < 32767) ? flash_mem[flash_idx] : 32'h0;
assign irdata_vld = iren;

// 数据读（组合逻辑）
wire [31:0] cpu_flash_offset = cpu_addr - FLASH_BASE;
wire [14:0] cpu_flash_idx = cpu_flash_offset[16:2];
assign cpu_rdata = (cpu_ren && cpu_flash_idx < 32767) ? flash_mem[cpu_flash_idx] : 32'h0;
assign cpu_rdata_vld = cpu_ren;

initial begin
    $readmemh("rtl/perips/flash_init.mem", flash_mem);
end

`endif

endmodule

`endif // FLASH_CTRL_SV