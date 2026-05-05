`ifndef CPU_AHB_IF_SV
`define CPU_AHB_IF_SV

// ============================================================
//  CPU AHB Interface - 将 CPU 流水线接口转换为 AHB-Lite Master
//
//  功能:
//    - 统一 IF 和 MEM 阶段的访问到单一 AHB-Lite 接口
//    - 处理流水线冲突（IF 和 MEM 同时访问）
//    - 生成 AHB-Lite 传输类型
//
//  注意: 这是简化的单周期 AHB-Lite 接口
// ============================================================
module CPU_AHB_IF (
    input  wire        clk,
    input  wire        rst,

    // ========== IF Stage Interface (Instruction Fetch) ==========
    input  wire [31:0] if_addr,       // IF stage address request
    input  wire        if_valid,       // IF stage requests valid
    output wire [31:0] if_rdata,      // IF stage read data
    output wire        if_ready,       // IF stage can accept result

    // ========== MEM Stage Interface (Data Memory) ==========
    input  wire [31:0] mem_addr,      // MEM stage address
    input  wire        mem_ren,        // MEM stage read enable
    input  wire        mem_wen,        // MEM stage write enable
    input  wire [3:0]  mem_be,        // MEM stage byte enable
    input  wire [31:0] mem_wdata,     // MEM stage write data
    output wire [31:0] mem_rdata,     // MEM stage read data
    output wire        mem_ready,      // MEM stage access complete

    // ========== AHB-Lite Master Interface ==========
    output wire [31:0] haddr,         // Address
    output wire        hsel,           // Select (always 1)
    output wire        hready_in,      // Master ready
    output wire [1:0]  htrans,        // Transfer type
    output wire        hwrite,         // Write enable
    output wire [2:0]  hsize,         // Size (0=8b, 1=16b, 2=32b)
    output wire [3:0]  hstrb,         // Byte strobe
    output wire [31:0] hwdata,        // Write data
    input  wire [31:0] hrdata,        // Read data
    input  wire        hreadyout,      // Transfer complete
    input  wire        hresp          // Response
);

    // ============================================================
    //  优先级仲裁
    //  MEM (data) 优先于 IF (instruction)
    //  因为数据访问通常更关键（可能阻塞流水线）
    // ============================================================

    // 访问请求判断
    wire if_request = if_valid;
    wire mem_request = mem_ren || mem_wen;

    // 优先级: MEM > IF
    reg grant_mem;
    reg grant_if;

    always @(*) begin
        grant_mem = 1'b0;
        grant_if = 1'b0;

        if (mem_request) begin
            grant_mem = 1'b1;
        end else if (if_request) begin
            grant_if = 1'b1;
        end
    end

    // ============================================================
    //  地址和数据选择
    // ============================================================

    wire [31:0] active_addr = grant_mem ? mem_addr : (grant_if ? if_addr : 32'h0);
    wire active_we = grant_mem ? mem_wen : 1'b0;
    wire active_re = grant_mem ? mem_ren : (grant_if ? 1'b1 : 1'b0);
    wire [3:0] active_be = grant_mem ? mem_be : 4'hF;  // IF uses full word
    wire [31:0] active_wdata = grant_mem ? mem_wdata : 32'h0;

    // ============================================================
    //  AHB-Lite 信号生成
    // ============================================================

    // 地址
    assign haddr = active_addr;

    // 选择信号（始终有效）
    assign hsel = grant_mem || grant_if;

    // 准备好接受新传输（当没有挂起访问时）
    assign hready_in = hreadyout || !hsel;

    // 传输类型: NONSEQ=2'b10 (开始传输), IDLE=2'b00 (空闲)
    assign htrans = hsel ? 2'b10 : 2'b00;

    // 写信号
    assign hwrite = active_we;

    // 数据大小: 32-bit = 3'b010
    assign hsize = 3'b010;

    // 字节使能
    assign hstrb = active_be;

    // 写数据
    assign hwdata = active_wdata;

    // ============================================================
    //  读数据返回
    // ============================================================

    // MEM 阶段读数据
    assign mem_rdata = (grant_mem && hreadyout) ? hrdata : 32'h0;

    // IF 阶段读数据
    assign if_rdata = (grant_if && hreadyout) ? hrdata : 32'h0;

    // 就绪信号
    assign if_ready = hreadyout && grant_if;
    assign mem_ready = hreadyout && grant_mem;

endmodule

`endif // CPU_AHB_IF_SV
