`timescale 1ns/1ps
module tb_debug;

reg clk = 0;
always #18.5185 clk = ~clk;

reg rst_n = 0;
initial begin
    #200 rst_n = 1;
end

// DUT
MyRiscV_soc_top dut (
    .clk(clk), .rst_n(rst_n),
    .uart_tx(), .uart_rx(1'b1),
    .jtag_tck(1'b0), .jtag_tms(1'b1), .jtag_tdi(1'b1), .jtag_tdo(),
    .jtag_trst_n(1'b1), .gpio_out(), .gpio_in(32'h0), .led()
);

// 监控D-BUS UART访问
reg [31:0] last_d_haddr;
reg last_d_trans_nonidle;

always @(posedge clk) begin
    if (rst_n) begin
        // D-BUS访问UART (0x1000_xxxx)
        if (dut.d_htrans != 2'b00 && dut.d_haddr[31:28] == 4'h1) begin
            $display("[%t] D-BUS UART: addr=0x%h, write=%b, wdata=0x%h, strb=0x%b, rdata=0x%h",
                     $time, dut.d_haddr, dut.d_hwrite, dut.d_hwdata, dut.d_hstrb, dut.d_hrdata);
        end

        // 监控UART寄存器
        if (dut.u_uart.tx_state != 0) begin
            $display("[%t] UART: state=%d, tx_data=0x%h, tx_out=%b",
                     $time, dut.u_uart.tx_state, dut.u_uart.tx_data, dut.u_uart.tx_out);
        end
    end
end

// 仿真时间限制
initial begin
    #100_000_000;
    $display("=== Timeout ===");
    $finish;
end

endmodule
