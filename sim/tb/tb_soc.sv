`timescale 1ns/1ps
// ============================================================
//  SoC 系统级仿真 Testbench
//  验证目标：CPU 执行 SimRAM 中的测试程序，通过 UART 输出 "Hello!\n"
//
//  时钟：27 MHz（周期 ~37ns，half-period 18ns）
//  复位：上电后 100ns 保持低电平（低有效复位），然后释放
//
//  UART 解码器：
//    - 监测 uart_tx 下降沿（起始位）
//    - 等待半个波特周期（4340ns @ 115200 bps）后对齐到位中点
//    - 依次采样 8 个数据位（LSB first）
//    - 接收到 '\n'（0x0A）后打印 "Simulation passed" 并结束
//
//  超时保护：10ms 后若未收到 '\n'，打印超时并结束
// ============================================================
module tb_soc;

// ---------------------------------------------------------
//  时钟生成（27 MHz，周期约 37.037 ns，half = 18 ns）
// ---------------------------------------------------------
reg clk = 1'b0;
always #18 clk = ~clk;  // 18ns half-period → 36ns period ≈ 27.78 MHz（近似 27 MHz）

// ---------------------------------------------------------
//  复位（低有效）
// ---------------------------------------------------------
reg rst_n = 1'b0;
initial begin
    #100;
    rst_n = 1'b1;   // 100ns 后释放复位
end

// ---------------------------------------------------------
//  顶层信号
// ---------------------------------------------------------
wire uart_tx;
wire uart_rx;
wire jtag_tdo;
wire [5:0] led;

// uart_rx 保持空闲电平（高）
assign uart_rx = 1'b1;

// ---------------------------------------------------------
//  DUT 例化
// ---------------------------------------------------------
MyRiscV_soc_top u_dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .uart_tx     (uart_tx),
    .uart_rx     (uart_rx),
    // JTAG：trst_n=1 不复位，其余接静态值（不使用 JTAG 功能）
    .jtag_tck    (1'b0),
    .jtag_tms    (1'b1),
    .jtag_tdi    (1'b1),
    .jtag_tdo    (jtag_tdo),
    .jtag_trst_n (1'b1),
    .led         (led)
);

// ---------------------------------------------------------
//  仿真基础设施：VCD 转储
// ---------------------------------------------------------
initial begin
    $dumpfile("sim/out/tb_soc.vcd");
    $dumpvars(0, tb_soc);
end

// ---------------------------------------------------------
//  UART 接收解码器
//  波特率：115200 bps
//  波特周期 = 1s / 115200 = 8680.555... ns，取 8681 ns
//  半波特周期 = 4340 ns（用于起始位中点对齐）
// ---------------------------------------------------------
localparam real BAUD_RATE    = 115200.0;
localparam real BAUD_PERIOD_NS = 1.0e9 / BAUD_RATE;    // ≈ 8680.6 ns
localparam real HALF_BAUD_NS   = BAUD_PERIOD_NS / 2.0; // ≈ 4340.3 ns

// 接收到的字符缓冲
reg [7:0] rx_char;
integer   rx_bit_idx;
reg [7:0] rx_byte;

// UART 接收任务（自动触发，监测 uart_tx 下降沿）
// 注意：测试程序通过 TX 发送，所以监测的是 uart_tx（CPU 发送端）
integer char_count;

initial begin : uart_rx_monitor
    char_count = 0;

    // 等待复位释放后再开始监测
    @(posedge rst_n);
    #1;  // 稳定一小段时间

    forever begin
        // 等待 uart_tx 下降沿（起始位开始）
        @(negedge uart_tx);

        // 等待半个波特周期，对齐到起始位中点，确认是真正的起始位
        #(HALF_BAUD_NS);

        if (uart_tx == 1'b0) begin
            // 确认是有效起始位，开始接收 8 个数据位
            rx_byte = 8'h00;

            // 采样 8 个数据位（LSB first，每隔一个波特周期采样一次）
            for (rx_bit_idx = 0; rx_bit_idx < 8; rx_bit_idx = rx_bit_idx + 1) begin
                #(BAUD_PERIOD_NS);  // 等待一个完整波特周期到达下一位中点
                rx_byte[rx_bit_idx] = uart_tx;
            end

            // 等待停止位（可选：检查停止位是否为 1）
            #(BAUD_PERIOD_NS);
            // 此时应处于停止位，uart_tx 应为 1

            // 打印接收到的字符
            char_count = char_count + 1;
            if (rx_byte >= 8'h20 && rx_byte < 8'h7F) begin
                // 可打印 ASCII 字符
                $display("[UART RX] char[%0d] = '%c' (0x%02X) at time %0t ns",
                         char_count, rx_byte, rx_byte, $time);
            end else begin
                $display("[UART RX] char[%0d] = 0x%02X (ctrl) at time %0t ns",
                         char_count, rx_byte, $time);
            end

            // 检查是否收到换行符（'\n' = 0x0A）
            if (rx_byte == 8'h0A) begin
                $display("===================================");
                $display("Simulation passed: received '\\n'");
                $display("===================================");
                $finish;
            end
        end
        // 如果不是有效起始位（毛刺），直接忽略，继续等待下一个下降沿
    end
end

// ---------------------------------------------------------
//  超时保护（10ms）
// ---------------------------------------------------------
initial begin
    #10_000_000;  // 10ms
    $display("[TIMEOUT] Simulation timeout at 10ms, did not receive '\\n'");
    $display("          Received %0d characters total", char_count);
    $finish;
end

// ---------------------------------------------------------
//  可选：监测 LED 状态变化（调试辅助）
// ---------------------------------------------------------
initial begin
    $display("[INFO] tb_soc started. Clock=27MHz, UART=115200bps");
    $display("[INFO] Waiting for 'Hello!\\n' on uart_tx...");
end

// 监测 LED 变化（可选调试信息）
reg [5:0] led_prev;
always @(posedge clk) begin
    if (led !== led_prev) begin
        led_prev <= led;
        // $display("[LED] changed to 0x%02X at time %0t ns", led, $time);
    end
end

endmodule
