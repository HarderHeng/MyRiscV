// ============================================================
// MyRiscV Hello World 仿真测试
// 验证 helloworld.bin 能否正确运行并输出 UART
// ============================================================
`timescale 1ns/1ps

module tb_helloworld;

// ---------------------------------------------------------
//  参数定义
// ---------------------------------------------------------
localparam CLK_PERIOD = 37;  // 27 MHz 时钟周期
localparam UART_BAUD = 115200;

// ---------------------------------------------------------
//  时钟和复位
// ---------------------------------------------------------
reg clk = 0;
reg rst_n = 0;

always #18.5 clk = ~clk;  // 27 MHz

initial begin
    rst_n = 0;
    #100;
    rst_n = 1;
end

// ---------------------------------------------------------
//  UART 信号
// ---------------------------------------------------------
wire uart_tx;
wire uart_rx = 1'b1;  // 悬空为高

// ---------------------------------------------------------
//  JTAG 信号（未使用，接地）
// ---------------------------------------------------------
wire jtag_tck = 0;
wire jtag_tms = 0;
wire jtag_tdi = 0;
wire jtag_tdo;
wire jtag_trst_n = 0;

// ---------------------------------------------------------
//  LED
// ---------------------------------------------------------
wire [5:0] led;

// ---------------------------------------------------------
//  例化 DUT (MyRiscV SoC)
// ---------------------------------------------------------
MyRiscV_soc_top u_soc (
    .clk        (clk),
    .rst_n      (rst_n),
    .uart_tx    (uart_tx),
    .uart_rx    (uart_rx),
    .jtag_tck   (jtag_tck),
    .jtag_tms   (jtag_tms),
    .jtag_tdi   (jtag_tdi),
    .jtag_tdo   (jtag_tdo),
    .jtag_trst_n(jtag_trst_n),
    .led        (led)
);

// ---------------------------------------------------------
//  IRAM 程序加载（覆盖默认初始化）
// ---------------------------------------------------------
// 注意：需要修改 IRAM 使其支持测试激励加载
// 或者使用 $readmemh 读取 helloworld.hex

// ---------------------------------------------------------
//  UART 接收监控（捕获 FPGA 输出）
// ---------------------------------------------------------
reg [7:0] uart_buffer [0:255];
integer uart_count = 0;
integer byte_idx = 0;

// 检测 UART TX 下降沿（起始位）
reg uart_tx_d1 = 1;
wire uart_falling_edge = uart_tx_d1 && !uart_tx;

// UART 位时间
real uart_bit_time = 1000000000.0 / UART_BAUD;  // ns
integer uart_half_bit = $rtoi(uart_bit_time / 2);
integer uart_full_bit = $rtoi(uart_bit_time);

// 采样定时器
reg [31:0] sample_timer = 0;
reg sampling = 0;
reg [7:0] rx_shift = 0;
reg [2:0] bit_count = 0;

always @(posedge clk) begin
    uart_tx_d1 <= uart_tx;

    if (uart_falling_edge && !sampling) begin
        // 检测起始位，等待半个位周期采样
        sampling <= 1;
        sample_timer <= uart_half_bit;
        bit_count <= 0;
        rx_shift <= 0;
    end

    if (sampling) begin
        if (sample_timer == 0) begin
            sample_timer <= uart_full_bit;
            if (bit_count < 8) begin
                // 采样数据位
                rx_shift[bit_count] <= uart_tx;
                bit_count <= bit_count + 1;
            end else begin
                // 采样完成（跳过停止位）
                uart_buffer[uart_count] <= rx_shift;
                uart_count <= uart_count + 1;
                sampling <= 0;
            end
        end else begin
            sample_timer <= sample_timer - 1;
        end
    end
end

// ---------------------------------------------------------
//  监控输出
// ---------------------------------------------------------
integer i;
initial begin
    $display("==============================================");
    $display("MyRiscV Hello World 仿真测试");
    $display("==============================================");
    $display("等待程序执行...");
end

// 超时检测
integer timeout = 0;
always @(posedge clk) begin
    timeout <= timeout + 1;
    if (timeout > 10000000) begin
        $display("[TIMEOUT] 程序执行超时!");
        $finish;
    end
end

// 检查接收到的字符
always @(posedge clk) begin
    if (uart_count > 0 && uart_buffer[uart_count-1] != 0) begin
        if (uart_buffer[uart_count-1] >= 32 && uart_buffer[uart_count-1] < 127) begin
            $write("[UART] %c", uart_buffer[uart_count-1]);
        end else if (uart_buffer[uart_count-1] == 10) begin
            $write("[UART] \\n\n");
        end else begin
            $write("[UART] 0x%02X", uart_buffer[uart_count-1]);
        end
    end
end

// 检查是否收到 "Hello, World!\n"
reg [13:0] expected [0:13];
integer check_idx = 0;
reg check_done = 0;

initial begin
    // "Hello, World!\n"
    expected[0] = "H";
    expected[1] = "e";
    expected[2] = "l";
    expected[3] = "l";
    expected[4] = "o";
    expected[5] = ",";
    expected[6] = " ";
    expected[7] = "W";
    expected[8] = "o";
    expected[9] = "r";
    expected[10] = "l";
    expected[11] = "d";
    expected[12] = "!";
    expected[13] = "\n";
end

always @(posedge clk) begin
    if (uart_count > check_idx && !check_done) begin
        if (uart_buffer[check_idx] == expected[check_idx]) begin
            check_idx <= check_idx + 1;
            if (check_idx == 14) begin
                check_done <= 1;
                $display("");
                $display("==============================================");
                $display("SUCCESS! Hello World 程序执行成功!");
                $display("==============================================");
                $display("输出内容：Hello, World!");
                $finish;
            end
        end else begin
            $display("");
            $display("==============================================");
            $display("ERROR! 收到意外字符：0x%02X (期望 0x%02X)",
                     uart_buffer[check_idx], expected[check_idx]);
            $display("==============================================");
            $finish;
        end
    end
end

// 波形输出
initial begin
    $dumpfile("tb_helloworld.vcd");
    $dumpvars(0, tb_helloworld);
end

endmodule
