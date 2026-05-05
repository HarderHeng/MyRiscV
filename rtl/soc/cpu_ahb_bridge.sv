`ifndef CPU_AHB_BRIDGE_SV
`define CPU_AHB_BRIDGE_SV

// ============================================================
//  CPU AHB Bridge - 将 CPU 的 iram_*/dbus_* 接口转换为 AHB-Lite
//
//  功能:
//    - 将 CPU 的指令端口和数据端口统一到单一 AHB-Lite 主设备接口
//    - 数据访问优先于指令访问
//    - 处理流水线暂停（当数据访问未完成时）
//
//  注意: 这是一个简化实现，假设所有访问都是单周期
// ============================================================
module CPU_AHB_Bridge (
    input  wire        clk,
    input  wire        rst,

    // ========== CPU Instruction Fetch Interface ==========
    input  wire [31:0] iram_addr,
    input  wire        iram_req,        // Instruction fetch request
    output wire [31:0] iram_rdata,
    output wire        iram_ready,

    // ========== CPU Data Interface ==========
    input  wire [31:0] dbus_addr,
    input  wire        dbus_ren,
    input  wire        dbus_wen,
    input  wire [3:0]  dbus_be,
    input  wire [31:0] dbus_wdata,
    output wire [31:0] dbus_rdata,
    output wire        dbus_ready,

    // ========== AHB-Lite Master Interface ==========
    output wire [31:0] haddr,
    output wire        hsel,
    output wire        hready_in,
    output wire [1:0]  htrans,
    output wire        hwrite,
    output wire [2:0]  hsize,
    output wire [3:0]  hstrb,
    output wire [31:0] hwdata,
    input  wire [31:0] hrdata,
    input  wire        hreadyout,
    input  wire        hresp
);

    // ============================================================
    //  请求检测
    // ============================================================
    wire if_req = iram_req;
    wire mem_req = dbus_ren || dbus_wen;

    // 优先级: 数据访问 > 指令访问
    reg grant_mem;
    reg grant_if;

    always @(*) begin
        grant_mem = 1'b0;
        grant_if = 1'b0;
        if (mem_req) begin
            grant_mem = 1'b1;
        end else if (if_req) begin
            grant_if = 1'b1;
        end
    end

    // ============================================================
    //  地址和数据选择
    // ============================================================
    wire [31:0] active_addr = grant_mem ? dbus_addr : (grant_if ? iram_addr : 32'h0);
    wire active_we = grant_mem ? dbus_wen : 1'b0;
    wire active_re = grant_mem ? dbus_ren : (grant_if ? 1'b1 : 1'b0);
    wire [3:0] active_be = grant_mem ? dbus_be : 4'hF;
    wire [31:0] active_wdata = grant_mem ? dbus_wdata : 32'h0;

    // ============================================================
    //  AHB-Lite 信号生成
    // ============================================================

    // 地址
    assign haddr = active_addr;

    // 选择信号
    assign hsel = grant_mem || grant_if;

    // 主设备就绪（当从设备就绪时）
    assign hready_in = hreadyout || !hsel;

    // 传输类型: NONSEQ=2'b10, IDLE=2'b00
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

    // 数据访问读数据
    assign dbus_rdata = (grant_mem && hreadyout) ? hrdata : 32'h0;

    // 指令访问读数据
    assign iram_rdata = (grant_if && hreadyout) ? hrdata : 32'h0;

    // 就绪信号
    assign dbus_ready = hreadyout && grant_mem;
    assign iram_ready = hreadyout && grant_if;

endmodule

`endif // CPU_AHB_BRIDGE_SV
