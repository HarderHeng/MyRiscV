# MyRiscV 快速上手指南

> 面向：熟悉 FPGA/RISC-V 基础、想快速跑通这个项目的工程师。
> 目标板：Sipeed Tang Nano 9K (GW1NR-9C)，工具链：OSS CAD Suite。

---

## 目录

1. [硬件连接](#1-硬件连接)
2. [环境准备](#2-环境准备)
3. [五分钟仿真](#3-五分钟仿真最快上手)
4. [FPGA 完整流程](#4-fpga-完整流程)
5. [查看 UART 输出](#5-查看-uart-输出)
6. [JTAG 调试](#6-jtag-调试)
7. [修改程序](#7-修改程序)
8. [快速参考卡](#8-快速参考卡)

---

## 1. 硬件连接

### 1.1 板子说明

| 功能 | 引脚 | 说明 |
|------|------|------|
| UART TX | 17 | 板载 USB-UART，接电脑后出现 /dev/ttyUSBx |
| UART RX | 18 | 同上 |
| 复位按键 S1 | 4 | 低有效，按下复位 CPU |
| LED0~LED5 | 10/11/13/14/15/16 | 低有效；LED5（引脚 16）亮 = CPU halted |

### 1.2 JTAG 接线（PMOD 排针 J4）

使用 FTDI 双通道调试器（如 FT2232H 模块）接 J4：

```
FTDI 模块          Tang Nano 9K (J4)
─────────          ─────────────────
TDI  ─────────────  引脚 75
TDO  ─────────────  引脚 74
TMS  ─────────────  引脚 76
TCK  ─────────────  引脚 77
TRST_N ───────────  引脚 73
GND  ─────────────  GND

J4 排针物理布局（俯视，USB 接口朝下）：
┌─────────────────────────┐
│  VCC  TMS  TDI  TDO     │
│  GND  TCK  TRST  (NC)   │
└─────────────────────────┘
  对应引脚：
  VCC     TMS(76)  TDI(75)  TDO(74)
  GND     TCK(77)  TRST(73) --
```

**注意：** UART 通过板载 USB-JTAG 芯片转换，插上 USB 线后会同时出现一个串口设备，无需额外接线。

---

## 2. 环境准备

### 2.1 工具检查清单

```bash
# 激活 OSS CAD Suite（每次新终端都要执行）
source /home/heng/oss-cad-suite/environment

# 验证各工具
iverilog -V          # 期望：Icarus Verilog version 12.x
yosys --version      # 期望：Yosys 0.x
nextpnr-gowin --version  # 期望：nextpnr-gowin -- Next Generation Place and Route
openocd --version    # 期望：Open On-Chip Debugger 0.x
riscv32-unknown-elf-gcc --version  # 期望：riscv32-unknown-elf-gcc (GCC) x.x
```

**如果 `riscv32-unknown-elf-gcc` 找不到：**

```bash
# Ubuntu/Debian
sudo apt install gcc-riscv64-unknown-elf
# 或从 https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack 下载预编译包
```

### 2.2 克隆项目

```bash
git clone <repo_url> MyRiscV
cd MyRiscV
```

### 2.3 目录结构速览

```
MyRiscV/
├── rtl/
│   ├── core/       # CPU 核心（core_define.svh, cpu_core.sv, ...）
│   ├── alu/        # ALU（alu.sv, alu.svh）
│   ├── debug/      # JTAG DTM + Debug Module
│   ├── perips/     # IRAM, DRAM, UART（iram_init.mem 是程序）
│   └── soc/        # SoC 顶层
├── sim/tb/         # Testbench
├── sw/test/        # C 测试程序源码
├── tools/          # 辅助脚本（mem2init.py 等）
├── syn/            # 综合约束、引脚分配
└── docs/           # 文档
```

---

## 3. 五分钟仿真（最快上手）

```bash
source /home/heng/oss-cad-suite/environment
cd /home/heng/study/MyRiscV

# ALU 单元测试
make sim_alu
```

预期输出：
```
ALU test PASS
```

```bash
# SoC 仿真（运行 Hello!\n 程序）
make sim_soc
```

预期输出：
```
[UART] H
[UART] e
[UART] l
[UART] l
[UART] o
[UART] !
[UART]
Simulation finished.
```

```bash
# 查看波形（可选）
make wave
```

GTKWave 会打开，加载 `sim/tb/tb_soc.vcd`，可以观察 CPU 流水线信号。

---

## 4. FPGA 完整流程

### 4.1 一键综合到烧录

```bash
source /home/heng/oss-cad-suite/environment
cd /home/heng/study/MyRiscV

# 步骤 1：生成 BSRAM 初始化参数（综合前必须执行，程序改动后也要重新执行）
python3 tools/mem2init.py rtl/perips/iram_init.mem

# 步骤 2：Yosys 综合
make synth
```

预期输出（末尾）：
```
...
Chip area for module '\MyRiscV_soc_top': xxxxxx
End of synthesis report
```

```bash
# 步骤 3：nextpnr 布局布线
make pnr
```

预期输出（末尾）：
```
...
Info: Program finished normally.
```

```bash
# 步骤 4：生成比特流
make bitstream
```

预期生成文件：`syn/out/MyRiscV.fs`

```bash
# 步骤 5：烧录（确保 Tang Nano 9K 已通过 USB 连接）
make prog
```

预期输出：
```
...
Programming DONE
```

### 4.2 烧录后验证

烧录完成后，板子自动复位并开始运行。观察：

- UART：打开串口工具，应看到 `Hello!` 输出（见第 5 节）
- LED：如 LED5 常亮，说明 CPU 处于 halted 状态，检查程序或 Debug Module 状态

### 4.3 常见问题

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| `make synth` 出现 `module not found` | svh include 路径问题 | 检查 Makefile 中 `INCDIRS_YOSYS` |
| `make prog` 提示找不到设备 | USB 未连接或驱动问题 | `lsusb` 确认 1d50:6130 或 0403:6010 |
| 烧录后无 UART 输出 | 波特率或程序问题 | 先跑 `make sim_soc` 确认程序正确 |
| nextpnr 报 `Placement failed` | 资源不足 | 检查 LUT/BSRAM 用量 |

---

## 5. 查看 UART 输出

Tang Nano 9K 板载 USB-UART，插 USB 后电脑出现串口设备：

```bash
# 查找串口设备
ls /dev/ttyUSB*
# 或
ls /dev/ttyACM*
```

**用 screen 连接（退出：Ctrl+A 然后 K）：**

```bash
screen /dev/ttyUSB0 115200
```

**用 minicom 连接（退出：Ctrl+A 然后 Q）：**

```bash
minicom -D /dev/ttyUSB0 -b 115200
```

**用 picocom 连接（退出：Ctrl+A 然后 Ctrl+X）：**

```bash
picocom -b 115200 /dev/ttyUSB0
```

预期看到：
```
Hello!
```

如果没有输出，按板子上的 S1 复位键再试。

**权限问题：**

```bash
sudo usermod -aG dialout $USER
# 重新登录后生效
```

---

## 6. JTAG 调试

### 6.1 创建 OpenOCD 配置文件

在项目根目录创建 `openocd.cfg`：

```tcl
adapter driver ftdi
ftdi_vid_pid 0x0403 0x6010
ftdi_layout_init 0x0008 0x000b
transport select jtag

set _CHIPNAME riscv
jtag newtap $_CHIPNAME cpu -irlen 5 -expected-id 0x01000563

set _TARGETNAME $_CHIPNAME.cpu
target create $_TARGETNAME riscv -chain-position $_TARGETNAME

init
halt
```

### 6.2 启动 OpenOCD

```bash
openocd -f openocd.cfg
```

预期输出：
```
Open On-Chip Debugger 0.x
Info : JTAG tap: riscv.cpu tap/device found: 0x01000563
Info : datacount=2 progbufsize=2
Info : Examined RISC-V core; found 1 harts
Info :  hart 0: XLEN=32, misa=0x...
Info : Listening on port 3333 for gdb connections
halted at 0x... due to debug-request
```

**如果报 `JTAG scan chain interrogation failed`：**
- 检查 JTAG 接线（TDI/TDO 是否接反）
- 检查 VCC/GND 是否连接
- 确认板子已烧录

### 6.3 GDB 调试

新开一个终端：

```bash
source /home/heng/oss-cad-suite/environment
riscv32-unknown-elf-gdb
```

```gdb
(gdb) target remote :3333
Remote debugging using :3333
0x80000000 in ?? ()

(gdb) info registers
# 输出所有寄存器值
# ra = 0x...  sp = 0x80005ff0  ...

(gdb) x/10i 0x80000000
# 反汇编 IRAM 起始 10 条指令
# 0x80000000:  addi  sp,sp,-32
# ...

(gdb) x/4w 0x80004000
# 查看 DRAM 起始 4 个字
# 0x80004000:  0x00000000  ...

(gdb) stepi
# 单步执行一条指令

(gdb) continue
# 恢复运行

(gdb) monitor halt
# 暂停 CPU

(gdb) set $pc = 0x80000000
# 修改 PC

(gdb) quit
```

### 6.4 常用 GDB 命令速查

| 命令 | 功能 |
|------|------|
| `info registers` | 查看所有寄存器 |
| `x/Ni 0xADDR` | 反汇编 N 条指令 |
| `x/Nw 0xADDR` | 读内存 N 个字 |
| `set $pc = 0xADDR` | 设置 PC |
| `stepi` | 单步（指令级） |
| `continue` | 继续运行 |
| `monitor halt` | 通过 OpenOCD 停止 CPU |
| `monitor reset halt` | 复位并停止 |

---

## 7. 修改程序

### 7.1 修改 C 程序并重新编译

```bash
# 编辑测试程序
vim sw/test/test.c

# 编译（生成 .elf 和 .bin）
make sw_test

# 反汇编查看（验证编译结果）
make sw_disasm
```

预期：`sw/test/test.dis` 中可以看到对应汇编代码。

### 7.2 更新 IRAM 程序

目前 `iram_init.mem` 是手工维护的 hex 格式机器码。如果你有 `.bin` 文件，可以用 `objcopy` 或自定义脚本转换：

```bash
# 将 ELF 转为原始二进制
riscv32-unknown-elf-objcopy -O binary sw/test/test.elf sw/test/test.bin

# 将 bin 转为 mem（每行一个 32bit 字，小端，hex 格式）
# 此步骤需要自定义脚本，示例：
python3 tools/bin2mem.py sw/test/test.bin rtl/perips/iram_init.mem
```

### 7.3 重新综合烧录

```bash
# 重新生成 BSRAM 初始化参数（必须！）
python3 tools/mem2init.py rtl/perips/iram_init.mem

# 重新综合 + 烧录（一步完成）
make synth && make pnr && make bitstream && make prog
```

### 7.4 UART 输出约定（供 C 程序参考）

```c
// UART 地址定义
#define UART_TXDATA  (*((volatile unsigned int *)0x10000000))
#define UART_STATUS  (*((volatile unsigned int *)0x10000008))
#define UART_TX_BUSY (1 << 0)

// 发送一个字节
void uart_putc(char c) {
    while (UART_STATUS & UART_TX_BUSY);  // 等待上一字节发送完成
    UART_TXDATA = (unsigned int)c;
}

// 发送字符串
void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}
```

---

## 8. 快速参考卡

### 地址映射

| 地址 | 大小 | 说明 |
|------|------|------|
| `0x80000000` | 16KB | IRAM（程序存储，$readmemh 初始化） |
| `0x80004000` | 8KB | DRAM（数据/栈） |
| `0x10000000` | 4B | UART TXDATA（写字节 = 发送） |
| `0x10000008` | 4B | UART STATUS（bit[0]=TX 忙） |
| `0x20000000` | 76KB | User Flash（只读，Phase 3） |
| `0x02000000` | - | CLINT Timer（Phase 4） |

### Makefile 命令

| 命令 | 功能 |
|------|------|
| `make sim_alu` | ALU 单元测试 |
| `make sim_soc` | SoC 仿真，验证 Hello!\n |
| `make wave` | GTKWave 查看波形 |
| `make synth` | Yosys 综合 |
| `make pnr` | nextpnr 布局布线 |
| `make bitstream` | 生成 .fs 比特流 |
| `make prog` | 烧录到 Tang Nano 9K |
| `make sw_test` | 编译 C 测试程序 |
| `make sw_disasm` | 反汇编查看 |
| `make clean` | 清理所有生成文件 |

### 引脚分配

| 功能 | 引脚 | 方向 | 说明 |
|------|------|------|------|
| CLK | 52 | 输入 | 27MHz 晶振 |
| RST_N (S1) | 4 | 输入 | 低有效复位 |
| UART TX | 17 | 输出 | 板载 USB-UART |
| UART RX | 18 | 输入 | 板载 USB-UART |
| LED[0] | 10 | 输出 | 低有效 |
| LED[1] | 11 | 输出 | 低有效 |
| LED[2] | 13 | 输出 | 低有效 |
| LED[3] | 14 | 输出 | 低有效 |
| LED[4] | 15 | 输出 | 低有效 |
| LED[5] (CPU halted) | 16 | 输出 | 低有效，亮 = CPU halted |
| JTAG TDI | 75 | 输入 | PMOD J4 |
| JTAG TDO | 74 | 输出 | PMOD J4 |
| JTAG TMS | 76 | 输入 | PMOD J4 |
| JTAG TCK | 77 | 输入 | PMOD J4 |
| JTAG TRST_N | 73 | 输入 | PMOD J4 |

### JTAG DTM IR 编码（5 位）

| IR | 寄存器 | 长度 | 说明 |
|----|--------|------|------|
| `5'h01` | IDCODE | 32bit | 芯片 ID |
| `5'h10` | DTMCS | 32bit | DTM 控制状态 |
| `5'h11` | DMI | 41bit | `{addr[6:0], data[31:0], op[1:0]}` |
| `5'h1F` | BYPASS | 1bit | 旁路 |

### 常用文件路径

| 文件 | 说明 |
|------|------|
| `rtl/perips/iram_init.mem` | IRAM 程序（hex，手工维护） |
| `rtl/core/core_define.svh` | CPU 全局宏定义 |
| `rtl/alu/alu.svh` | ALU 操作码定义 |
| `rtl/soc/MyRiscV_soc_top.sv` | SoC 顶层 |
| `sim/tb/tb_soc.sv` | SoC Testbench |
| `syn/out/MyRiscV.fs` | 综合生成的比特流 |
| `docs/design_spec.md` | 完整设计规格（v0.3） |
