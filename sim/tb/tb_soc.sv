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
//  CPU 活动监控
// ---------------------------------------------------------
reg [31:0] cycle_count;
reg [31:0] last_uart_write;
initial begin
    cycle_count = 0;
    last_uart_write = 0;
end
always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
end
// ---------------------------------------------------------
reg clk = 1'b0;
reg [31:0] sim_cycle;
reg [31:0] last_pc;
reg [31:0] pc_change_count;
initial begin
    sim_cycle = 0;
    last_pc = 0;
    pc_change_count = 0;
end
always #18 clk = ~clk;
always @(posedge clk) begin
    sim_cycle <= sim_cycle + 1;
end  // 18ns half-period → 36ns period ≈ 27.78 MHz（近似 27 MHz）

// ---------------------------------------------------------
//  复位（低有效）
// ---------------------------------------------------------
reg rst_n = 1'b0;
initial begin
    #200;  // 延长复位时间，确保存储器初始化完成
    rst_n = 1'b1;
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
// ---------------------------------------------------------
//  PC and UART Monitoring
// ---------------------------------------------------------
reg [31:0] dbg_pc;
reg [31:0] dbg_pc_prev;
reg [31:0] pc_stuck_count;
reg [7:0] dbg_tx_char;
reg dbg_tx_wr;
reg [31:0] uart_write_count;
reg [31:0] last_uart_write_time;
reg [31:0] last_uart_char;
reg [3:0] prev_tx_state;
reg tx_state_started;

initial begin
    dbg_pc_prev = 0;
    pc_stuck_count = 0;
    dbg_tx_char = 0;
    dbg_tx_wr = 0;
    uart_write_count = 0;
    last_uart_write_time = 0;
    last_uart_char = 0;
    prev_tx_state = 0;
    tx_state_started = 0;
end

always @(posedge clk) begin
    dbg_pc <= u_dut.u_cpu.u_if.pc;
    if (dbg_pc == dbg_pc_prev && u_dut.rst) begin
        pc_stuck_count <= pc_stuck_count + 1;
    end else begin
        pc_stuck_count <= 0;
    end
    dbg_pc_prev <= dbg_pc;

    // Detect TX state machine leaving IDLE
    if (prev_tx_state == 0 && u_dut.u_uart.tx_state != 0 && !tx_state_started) begin
        tx_state_started <= 1;
        $display("[TX STATE] First TX started! state=%d tx_data=0x%02h at time %0t ns",
                 u_dut.u_uart.tx_state, u_dut.u_uart.tx_data, $time);
    end
    prev_tx_state <= u_dut.u_uart.tx_state;

    // Monitor UART TX state - detect character sends
    if (u_dut.u_uart.tx_state == 1 && u_dut.u_uart.tx_clk_cnt == 0) begin
        // TX_START state beginning - this is when a new char is loaded
        uart_write_count <= uart_write_count + 1;
        last_uart_write_time <= $time;
        last_uart_char <= u_dut.u_uart.tx_data;
        $display("[UART WRITE] #%0d char=0x%02h '%c' at time %0t ns, PC=0x%h",
                 uart_write_count + 1, u_dut.u_uart.tx_data,
                 (u_dut.u_uart.tx_data >= 32 && u_dut.u_uart.tx_data < 127) ? u_dut.u_uart.tx_data : ".",
                 $time, u_dut.u_cpu.u_if.pc);
    end

    // Monitor UART STAT reads (dbus_addr == 0x10000008 and dbus_ren)
    if (u_dut.u_cpu.dbus_ren && u_dut.u_cpu.dbus_addr == 32'h10000008) begin
        $display("[UART STAT READ] data=0x%h at time %0t ns, PC=0x%h",
                 u_dut.u_cpu.dbus_rdata, $time, u_dut.u_cpu.u_if.pc);
    end

    // Monitor UART TX writes (dbus_addr == 0x10000000 and dbus_wen)
    if (u_dut.u_cpu.dbus_wen && u_dut.u_cpu.dbus_addr == 32'h10000000) begin
        $display("[UART TX WRITE] data=0x%02h '%c' at time %0t ns, PC=0x%h",
                 u_dut.u_cpu.dbus_wdata[7:0],
                 (u_dut.u_cpu.dbus_wdata[7:0] >= 32 && u_dut.u_cpu.dbus_wdata[7:0] < 127) ? u_dut.u_cpu.dbus_wdata[7:0] : ".",
                 $time, u_dut.u_cpu.u_if.pc);
    end
end

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
    .gpio_out    (),
    .gpio_in     (32'h0),
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
    $display("[DEBUG] led = %b", u_dut.led);
    $display("[DEBUG] Instruction at flash[0] = 0x%h", u_dut.u_flash.flash_mem[0]);
    $display("[DEBUG] Instruction at flash[1] = 0x%h", u_dut.u_flash.flash_mem[1]);
    $display("  flash[0] = 0x%h (PC=0x20000000)", u_dut.u_flash.flash_mem[0]);
    $display("  flash[1] = 0x%h (PC=0x20000004)", u_dut.u_flash.flash_mem[1]);
    $display("  flash[2] = 0x%h (PC=0x20000008)", u_dut.u_flash.flash_mem[2]);
    $display("  flash[3] = 0x%h (PC=0x2000000c)", u_dut.u_flash.flash_mem[3]);
    $display("  flash[4] = 0x%h (PC=0x20000010)", u_dut.u_flash.flash_mem[4]);
    $display("  flash[5] = 0x%h (PC=0x20000014)", u_dut.u_flash.flash_mem[5]);
    $display("  flash[6] = 0x%h (PC=0x20000018)", u_dut.u_flash.flash_mem[6]);
    $display("  flash[7] = 0x%h (PC=0x2000001c)", u_dut.u_flash.flash_mem[7]);
    $display("  flash[21] = 0x%h (string 'Hell')", u_dut.u_flash.flash_mem[21]);
    $display("  flash[22] = 0x%h (string 'o, W')", u_dut.u_flash.flash_mem[22]);
    $display("  flash[23] = 0x%h (string 'orld')", u_dut.u_flash.flash_mem[23]);
    $display("  flash[24] = 0x%h (string end)", u_dut.u_flash.flash_mem[24]);
    $display("  flash[25] = 0x%h (should be 0)", u_dut.u_flash.flash_mem[25]);
    
    // Debug: Check if CPU is fetching instructions
    $display("[DEBUG] CPU state at timeout:");
    $display("  iram_addr at timeout = 0x%h", u_dut.u_cpu.u_if.pc);
    $display("  dbg_pc_stuck = %d", pc_stuck_count);
    $display("  dbus_addr = 0x%h", u_dut.u_cpu.dbus_addr);
    $display("  CPU if_id state: inst=0x%h, pc=0x%h", 
             u_dut.u_cpu.u_if_id.id_inst, u_dut.u_cpu.u_if_id.id_pc);
    $display("  UART tx_state=%d, tx_busy=%d", 
             u_dut.u_uart.tx_state, u_dut.u_uart.tx_busy);
    $display("  dbus_ren = %b, dbus_wen = %b", u_dut.u_cpu.dbus_ren, u_dut.u_cpu.dbus_wen);
    $finish;
end

// ---------------------------------------------------------
//  可选：监测 LED 状态变化（调试辅助）
// ---------------------------------------------------------
initial begin
    $display("[INFO] tb_soc started. Clock=27MHz, UART=115200bps");
    $display("[INFO] Reset released at time %0t ns", $time);
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
