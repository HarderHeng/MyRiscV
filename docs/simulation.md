# MyRiscV 仿真使用文档

> 面向 RTL 工程师的完整仿真指南。基于 OSS CAD Suite iverilog + GTKWave。

---

## 1. 快速开始

两步即可跑通全系统仿真：

```bash
# 第 1 步：激活工具链
source /home/heng/oss-cad-suite/environment

# 第 2 步：在项目根目录运行 SoC 仿真
cd /home/heng/study/MyRiscV
make sim_soc
```

正常输出末尾应出现：

```
===================================
Simulation passed: received '\n'
===================================
```

---

## 2. 环境准备

### 2.1 激活 OSS CAD Suite

```bash
source /home/heng/oss-cad-suite/environment
```

激活后验证工具可用：

```bash
iverilog -V   # 应显示 Icarus Verilog 版本
vvp --version
gtkwave --version
```

### 2.2 确认 .mem 文件存在

仿真依赖两个初始化文件，**必须从项目根目录运行 make**（相对路径基准为 make 运行目录）：

| 文件 | 用途 | 说明 |
|------|------|------|
| `rtl/perips/iram_init.mem` | IRAM 程序 | 存放 Hello!\n 测试程序的机器码，hex 格式 |
| `rtl/perips/flash_init.mem` | Flash 占位 | 全零占位文件，仿真不使用 Flash 时也必须存在 |

检查文件是否存在：

```bash
ls -lh rtl/perips/iram_init.mem rtl/perips/flash_init.mem
```

若 `flash_init.mem` 缺失，iverilog 运行时会报 `$readmemh` 警告或错误。可用全零文件创建占位：

```bash
python3 -c "print('\n'.join(['00000000']*32768))" > rtl/perips/flash_init.mem
```

### 2.3 创建输出目录

`make` 会自动创建 `sim/out/`，也可手动创建：

```bash
mkdir -p sim/out
```

---

## 3. 仿真目标说明

### 3.1 `make sim_alu` — ALU 单元测试

- 测试对象：`rtl/alu/alu.sv`（模块名 `RvALU`）
- Testbench：`sim/tb/tb_alu.sv`
- 测试内容：12 种 ALU 操作，共 36 个测试向量，纯组合逻辑验证
- 无时钟，每个向量等待 `#1` 稳定后检查结果
- 全部通过时输出 `ALL PASS`，失败时 `$error` 打印具体向量

### 3.2 `make sim_soc` — SoC 系统仿真

- 测试对象：全系统（CPU 核 + IRAM + DRAM + UART + Debug）
- Testbench：`sim/tb/tb_soc.sv`
- 验证目标：CPU 执行 IRAM 中的程序，通过 UART TX 输出 `Hello!\n`
- UART 解码器自动采样 uart_tx，收到 `\n`（0x0A）后打印通过并结束
- 超时保护：10ms 内未收到 `\n` 则报超时
- VCD 波形转储到 `sim/out/tb_soc.vcd`

### 3.3 `make wave` — 打开 GTKWave

```bash
make wave
```

打开 `sim/out/tb_soc.vcd`（GTKWave 在后台运行）。需先运行过 `make sim_soc` 生成 VCD 文件。

### 3.4 `make clean` — 清理输出

```bash
make clean
```

删除 `sim/out/` 和 `syn/out/` 目录下所有生成文件。

---

## 4. 手动编译命令

当需要单步调试编译错误时，可绕过 Makefile 直接运行：

### 4.1 ALU 仿真手动编译

```bash
# 在项目根目录执行
iverilog -g2012 \
    -I rtl/alu \
    -I rtl/core \
    -o sim/out/tb_alu \
    rtl/alu/alu.sv \
    sim/tb/tb_alu.sv

# 运行仿真
vvp sim/out/tb_alu
```

### 4.2 SoC 仿真手动编译

```bash
# 在项目根目录执行（注意：不加 -DSYNTHESIS，保持行为模型路径）
iverilog -g2012 \
    -I rtl/alu \
    -I rtl/core \
    -o sim/out/tb_soc \
    rtl/alu/alu.sv \
    rtl/core/regfile.sv \
    rtl/core/if.sv \
    rtl/core/if_id.sv \
    rtl/core/id.sv \
    rtl/core/id_ex.sv \
    rtl/core/ex.sv \
    rtl/core/ex_mem.sv \
    rtl/core/mem.sv \
    rtl/core/mem_wb.sv \
    rtl/core/hazard.sv \
    rtl/core/cpu_core.sv \
    rtl/debug/jtag_dtm.sv \
    rtl/debug/debug_module.sv \
    rtl/perips/uart.sv \
    rtl/perips/iram.sv \
    rtl/perips/dram.sv \
    rtl/perips/flash_ctrl.sv \
    rtl/soc/MyRiscV_soc_top.sv \
    sim/tb/tb_soc.sv

# 运行仿真（生成 VCD）
vvp sim/out/tb_soc
```

**重要**：`-I` 格式是 OSS CAD Suite iverilog 的正确用法，不支持 VCS/NC 风格的 `+incdir+`。

### 4.3 时间精度说明

所有文件使用 `` `timescale 1ns/1ps ``：

- `$time` 返回值单位是 1ps（精度单位）
- `$display` 打印 `$time` 时需除以 1000 才是 ns，例如：

```systemverilog
$display("time = %0t ns", $time / 1000);
// 或者在 display 格式中直接打印 ps：
$display("time = %0t ps", $time);
```

testbench 中 `$display("[UART RX] ... at time %0t ns", $time)` 的 ns 标注与实际单位不符（实际输出是 ps 值），阅读时注意将打印数值除以 1000 换算为 ns。

---

## 5. 仿真输出解读

### 5.1 ALU 正常输出

```
=== ALU Unit Test ===
=== Results: 36 passed, 0 failed ===
ALL PASS
```

### 5.2 ALU 失败输出示例

```
=== ALU Unit Test ===
ERROR: sim/tb/tb_alu.sv:46: [FAIL] ADD norm  : src1=0x00000001 src2=0x00000001 expected=0x00000002 got=0x00000000
=== Results: 35 passed, 1 failed ===
SOME TESTS FAILED
```

### 5.3 SoC 正常输出

```
[INFO] tb_soc started. Clock=27MHz, UART=115200bps
[INFO] Waiting for 'Hello!\n' on uart_tx...
[UART RX] char[1] = 'H' (0x48) at time 2135000000 ps
[UART RX] char[2] = 'e' (0x65) at time 2223000000 ps
[UART RX] char[3] = 'l' (0x6C) at time 2311000000 ps
[UART RX] char[4] = 'l' (0x6C) at time 2399000000 ps
[UART RX] char[5] = 'o' (0x6F) at time 2487000000 ps
[UART RX] char[6] = '!' (0x21) at time 2575000000 ps
[UART RX] char[7] = 0x0A (ctrl) at time 2663000000 ps
===================================
Simulation passed: received '\n'
===================================
```

时间列为 ps 单位，除以 1000 得 ns（例如 2135000000 ps = 2135000 ns ≈ 2.1ms）。

### 5.4 SoC 超时输出

```
[INFO] tb_soc started. Clock=27MHz, UART=115200bps
[INFO] Waiting for 'Hello!\n' on uart_tx...
[UART RX] char[1] = 'H' (0x48) at time 2135000000 ps
[TIMEOUT] Simulation timeout at 10ms, did not receive '\n'
          Received 1 characters total
```

若收到部分字符后超时，说明程序执行卡死或 UART 发送中断。若收到 0 个字符，说明 CPU 没有执行到 UART 发送代码。

### 5.5 SoC 编译报错示例

```
# flash_init.mem 缺失时
rtl/perips/flash_ctrl.sv:97: error: Failed to open iram_init.mem for reading.
```

此时检查是否在项目根目录运行（`pwd` 应输出 `/home/heng/study/MyRiscV`）。

---

## 6. 调试技巧

### 6.1 用 GTKWave 查看波形

```bash
make sim_soc   # 先生成 VCD
make wave      # 打开 GTKWave
```

在 GTKWave 中查找关键信号的层次路径：

| 信号 | GTKWave 路径 | 说明 |
|------|-------------|------|
| `uart_tx` | `tb_soc.u_dut.uart_tx` | UART 发送线，可直接看波形确认发送 |
| `pc`（程序计数器）| `tb_soc.u_dut.u_cpu_core.u_if.pc` | IF 阶段当前 PC |
| `if_hold` | `tb_soc.u_dut.u_cpu_core.u_if.if_hold` | IF 阶段暂停信号 |
| `iram_wait` | `tb_soc.u_dut.u_cpu_core.iram_wait` | IRAM 等待信号（仿真路径恒 0）|
| `id_inst` | `tb_soc.u_dut.u_cpu_core.u_if_id.id_inst` | ID 阶段当前指令 |
| `dbus_addr` | `tb_soc.u_dut.u_cpu_core.dbus_addr` | 数据总线地址 |
| `dbus_wdata` | `tb_soc.u_dut.u_cpu_core.dbus_wdata` | 数据总线写数据 |
| `led` | `tb_soc.u_dut.led` | LED 输出（调试观测点）|

操作步骤：
1. GTKWave 左侧 SST 面板展开层次
2. 双击信号名添加到波形区
3. 按 `Ctrl+A` 全选，`Ctrl+F` 适配时间轴
4. 右键信号可切换 Hex/Binary/Decimal 显示格式

### 6.2 增加仿真超时时间

若程序执行时间超过 10ms（例如添加了较复杂的逻辑），临时修改 `sim/tb/tb_soc.sv`：

```systemverilog
// 原来（第 144 行）：
#10_000_000;  // 10ms

// 改为（例如 50ms）：
#50_000_000;  // 50ms
```

修改后需重新编译：

```bash
make sim_soc
```

### 6.3 添加自定义打印

在 `sim/tb/tb_soc.sv` 中添加 `$display` 观测内部信号：

```systemverilog
// 在 initial begin 块中，或 always @(posedge clk) 中添加：

// 示例 1：周期性打印 PC（每 100 个时钟周期打印一次）
integer cycle_cnt;
always @(posedge clk) begin
    cycle_cnt <= cycle_cnt + 1;
    if (cycle_cnt % 100 == 0)
        $display("[DBG] cycle=%0d PC=0x%08X", cycle_cnt,
                 u_dut.u_cpu_core.u_if.pc);
end

// 示例 2：打印所有数据总线写操作
always @(posedge clk) begin
    if (u_dut.u_cpu_core.dbus_wen)
        $display("[MEM WR] addr=0x%08X data=0x%08X be=%b",
                 u_dut.u_cpu_core.dbus_addr,
                 u_dut.u_cpu_core.dbus_wdata,
                 u_dut.u_cpu_core.dbus_be);
end
```

### 6.4 内部信号层次路径参考

```
tb_soc                              ← testbench 顶层
└── u_dut (MyRiscV_soc_top)
    ├── u_cpu_core (cpu_core)
    │   ├── u_if     (riscv_if)     ← IF 阶段：.pc, .if_hold
    │   ├── u_if_id  (riscv_if_id)  ← IF/ID 流水寄存器：.id_inst, .id_pc
    │   ├── u_id     (riscv_id)     ← ID 阶段：.rs1_data, .rs2_data
    │   ├── u_id_ex  (riscv_id_ex)
    │   ├── u_ex     (riscv_ex)     ← EX 阶段：.alu_result
    │   ├── u_ex_mem (riscv_ex_mem)
    │   ├── u_mem    (riscv_mem)    ← MEM 阶段
    │   ├── u_mem_wb (riscv_mem_wb)
    │   ├── u_hazard (hazard)       ← 冒险检测：.stall, .flush
    │   └── u_regfile (regfile)     ← 寄存器堆
    ├── u_iram   (IRAM)             ← 指令 RAM
    ├── u_dram   (DRAM)             ← 数据 RAM
    ├── u_uart   (uart)             ← UART：.tx_busy, .tx_data
    ├── u_flash  (FlashCtrl)        ← Flash 控制器
    ├── u_jtag_dtm  (jtag_dtm)
    └── u_debug_module (debug_module)
```

### 6.5 仿真路径 vs 综合路径的差异

IRAM 和 FlashCtrl 均有 `` `ifdef SYNTHESIS `` 分支：

- **仿真路径**（不加 `-DSYNTHESIS`）：`$readmemh` 行为模型，IRAM 组合读（无延迟），`iram_wait` 不影响功能
- **综合路径**（加 `-DSYNTHESIS`）：Gowin SDPB/FLASH608K 原语，IRAM 同步读（1 周期延迟），需要 `iram_wait` 机制

仿真时**不要**加 `-DSYNTHESIS`，否则 SDPB/FLASH608K 原语无法在 iverilog 中找到定义。

---

## 7. 测试覆盖说明

### 7.1 tb_alu 36 个测试向量

| # | 操作 | 测试名 | 测试内容 |
|---|------|--------|---------|
| 1 | ADD | ADD norm | 1 + 1 = 2（基础加法）|
| 2 | ADD | ADD wrap | 0xFFFFFFFF + 1 = 0（32位溢出回绕）|
| 3 | ADD | ADD ovfl | 0x80000000 + 0x80000000 = 0（符号溢出）|
| 4 | ADD | ADD zero | 0 + 0 = 0 |
| 5 | SUB | SUB norm | 5 - 3 = 2 |
| 6 | SUB | SUB wrap | 0 - 1 = 0xFFFFFFFF（负结果回绕）|
| 7 | SUB | SUB self | a - a = 0 |
| 8 | XOR | XOR comp | 互补掩码 XOR = 全 1 |
| 9 | XOR | XOR self | a XOR a = 0 |
| 10 | XOR | XOR zero | a XOR 0 = a |
| 11 | OR | OR full | 高低半字 OR = 全 1 |
| 12 | OR | OR zero | 0 OR 0 = 0 |
| 13 | AND | AND mask | 全 1 AND mask = mask |
| 14 | AND | AND zero | a AND 0 = 0 |
| 15 | SLL | SLL by1 | 左移 1 位 |
| 16 | SLL | SLL by31 | 左移 31 位，结果为 0x80000000 |
| 17 | SLL | SLL by32 | 左移 32 位（mod32），等同于移 0 位 |
| 18 | SLL | SLL mask | 左移 8 位，低 8 位清零 |
| 19 | SRL | SRL by1 | 逻辑右移 1 位，高位补 0 |
| 20 | SRL | SRL by8 | 逻辑右移 8 位 |
| 21 | SRL | SRL by31 | 逻辑右移 31 位，结果为 1 |
| 22 | SRA | SRA neg1 | 负数算术右移 1 位，高位补 1 |
| 23 | SRA | SRA neg8 | -1 算术右移 8 位，结果仍 -1 |
| 24 | SRA | SRA pos1 | 正数算术右移 1 位，高位补 0 |
| 25 | SRA | SRA by31 | 负数算术右移 31 位，结果为全 1 |
| 26 | SLT | SLT pos\<p | 1 < 2（有符号），结果 1 |
| 27 | SLT | SLT pos\>p | 2 > 1（有符号），结果 0 |
| 28 | SLT | SLT neg\<p | -1 < 1（有符号），结果 1 |
| 29 | SLT | SLT pos\>n | 1 > -1（有符号），结果 0 |
| 30 | SLT | SLT equal | a == a，结果 0 |
| 31 | SLTU | SLTU \< | 1 < 2（无符号），结果 1 |
| 32 | SLTU | SLTU big\>s | 0xFFFFFFFF > 1（无符号），结果 0 |
| 33 | SLTU | SLTU 0\<max | 0 < 0xFFFFFFFF（无符号），结果 1 |
| 34 | COPY_A | COPY_A | 直通 src1，用于 LUI |
| 35 | COPY_A | COPY_A lui | LUI 场景（高 20 位立即数直通）|
| 36 | COPY_B | COPY_B | 直通 src2 |

### 7.2 tb_soc 功能覆盖

| 功能 | 验证方式 | 覆盖范围 |
|------|---------|---------|
| CPU 取指 | UART 输出正确字符串 | IF 阶段、PC 递增、IRAM 读 |
| CPU 译码执行 | 程序能执行到 UART 发送 | ID/EX 阶段、立即数扩展、跳转 |
| UART 发送 | UART 解码器收到 7 个字节 | UART TX 时序（8N1 115200bps）|
| 内存映射 | UART 寄存器地址 0x10000000 被正确路由 | 地址译码、总线仲裁 |
| 复位行为 | 100ns 后释放，之后 PC 从正确地址开始 | 同步高有效复位 |
| JTAG 静态 | JTAG 引脚接静态值，仿真不崩溃 | JTAG DTM 复位状态 |

---

## 8. 常见问题（FAQ）

**Q: `$readmemh: Failed to open` 错误**

A: 必须在项目根目录（`/home/heng/study/MyRiscV`）运行 make，不能在子目录。`iram.sv` 和 `flash_ctrl.sv` 中的路径 `rtl/perips/iram_init.mem` / `rtl/perips/flash_init.mem` 是相对于 `vvp` 运行目录的。

```bash
cd /home/heng/study/MyRiscV
make sim_soc   # 正确
```

---

**Q: `iverilog: error: Unknown module type: SDPB`**

A: 编译时加了 `-DSYNTHESIS` 宏，导致 IRAM 走了 Gowin 原语路径，iverilog 没有 SDPB 原语定义。仿真不需要加该宏，Makefile 中已正确配置。

---

**Q: 超时，收到 0 个字符**

原因排查顺序：
1. 检查 `iram_init.mem` 是否正确（含 Hello!\n 测试程序）
2. 用 GTKWave 查看 `pc` 是否在递增——若 PC 停在 0x80000000 不动，说明 IRAM 读出全零（`.mem` 文件为空或路径错误）
3. 查看 `uart_tx` 是否有波形变化——若始终为 1（空闲），说明程序没有执行到 UART 发送
4. 检查地址映射：UART 基地址 0x10000000，查看 `dbus_addr` 是否出现该地址

---

**Q: 超时，收到部分字符（如收到 "Hel" 就停了）**

A: 程序执行卡死，可能是：
- 流水线死锁（hazard 单元问题）
- UART 发送 busy 等待死循环（轮询 TX 忙状态位时被卡住）
- 检查 `u_dut.u_uart.tx_busy` 是否一直为 1

---

**Q: GTKWave 打开后看不到信号**

A: 确认 VCD 文件已生成：

```bash
ls -lh sim/out/tb_soc.vcd
```

若文件不存在或大小为 0，说明仿真在 `$dumpvars` 之前就崩溃了（编译阶段错误已被忽略，或运行时立即 fatal）。重新运行 `vvp sim/out/tb_soc` 检查报错。

---

**Q: `make sim_soc` 编译通过但 vvp 立即退出，无任何输出**

A: 检查 `timescale` 是否一致。若某个源文件缺少 `` `timescale 1ns/1ps ``，iverilog 可能产生时间精度警告甚至行为异常。所有源文件顶部均应有该声明。

---

**Q: ALU 某项失败，提示 `got=0xXXXXXXXX`**

A: 对照第 7.1 节测试向量列表，找到对应操作码，检查 `rtl/alu/alu.sv` 中该操作的实现。`alu_op` 编码定义在 `rtl/alu/alu.svh` 中（`ALU_ADD`、`ALU_SUB` 等宏）。

---

**Q: 修改了 RTL 文件，仿真没有变化**

A: Makefile 依赖检查基于文件时间戳。若修改后时间戳未更新（罕见），强制重新编译：

```bash
make clean && make sim_soc
```

---

**Q: `iverilog` 命令找不到**

A: 未激活 OSS CAD Suite 环境：

```bash
source /home/heng/oss-cad-suite/environment
which iverilog   # 应输出 /home/heng/oss-cad-suite/bin/iverilog
```
