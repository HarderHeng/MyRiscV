# MyRiscV Hello World

通过 UART 输出 "Hello, World!\n" 的独立汇编程序。

## 文件结构

```
sw/helloworld/
├── helloworld.s      # 汇编源代码
├── link.ld           # 链接脚本
├── build.sh          # 简单构建脚本
├── build_all.sh      # 完整构建脚本
├── openocd.cfg       # OpenOCD 配置
└── README.md         # 本文档
```

## 快速开始

### 1. 编译程序

```bash
./build.sh
# 或
./build_all.sh build
```

输出：
- `helloworld.elf` - ELF 可执行文件（用于调试）
- `helloworld.bin` - 纯二进制（用于 JTAG 烧录）
- `helloworld.hex` - Verilog hex 格式（用于仿真）

### 2. 查看反汇编

```bash
./build.sh disasm
# 或
./build_all.sh disasm
```

### 3. 通过 JTAG 烧录到 Flash

```bash
# 修改 openocd.cfg 以匹配你的 JTAG 适配器
./build_all.sh flash
```

程序将被烧录到片上 Flash，起始地址 `0x20000000`。

## 程序说明

### 内存布局

| 段 | 地址 | 大小 | 说明 |
|----|------|------|------|
| .text | 0x80000000 | 84 字节 | 代码段（IRAM） |
| .rodata | 0x80000054 | 16 字节 | 字符串常量（IRAM） |
| .bss | 0x80004000 | 0 字节 | 未初始化数据（DRAM） |
| 栈 | 0x80006000 | - | 栈顶（DRAM 顶部） |

### UART 寄存器

| 地址 | 名称 | 访问 | 说明 |
|------|------|------|------|
| 0x10000000 | UART_TX | 写 | 发送数据寄存器 |
| 0x10000004 | UART_RX | 读 | 接收数据寄存器 |
| 0x10000008 | UART_STAT | 读 | 状态寄存器 |

状态寄存器位：
- Bit 0: TX_READY（发送就绪）

### 执行流程

1. `_start`: 设置栈指针到 0x80006000
2. 跳转到 `main`
3. `main`: 循环读取字符串 "Hello, World!\n"
4. 每个字符通过 UART_TX 发送
5. 发送完成后返回死循环

## JTAG 烧录说明

### 硬件连接

```
Tang Nano 9K          JTAG 适配器 (FT2232)
----------------      ------------------
jtag_tck (PMOD_1)  <- TCK
jtag_tms (PMOD_2)  <- TMS
jtag_tdi (PMOD_3)  <- TDI
jtag_tdo (PMOD_4)  -> TDO
jtag_trst_n        <- TRST (可选)
GND                <- GND
```

### OpenOCD 配置

编辑 `openocd.cfg`：

```tcl
# 根据你的适配器修改
adapter driver ftdi
ftdi_device_desc "Dual RS232-HS"
ftdi_vid_pid 0x0403 0x6010
adapter speed 1000
```

### 烧录命令

```bash
# 方法 1: 使用构建脚本
./build_all.sh flash

# 方法 2: 直接使用 OpenOCD
openocd -f openocd.cfg \
  -c "program helloworld.bin 0x20000000 verify reset exit"
```

## 仿真验证

在 testbench 中加载程序：

```verilog
// 在 tb_soc.sv 中
initial begin
    $readmemh("helloworld.hex", u_soc.mem_array);
end
```

或使用 hex 文件替换 `rtl/perips/iram_init.mem` 重新综合。

## 工具链

- 编译器：`riscv64-unknown-elf-gcc`
- 架构：RV32I (`-march=rv32i -mabi=ilp32`)
- 模式：裸机 (`-nostdlib -ffreestanding -nostartfiles`)

## 故障排除

### 编译错误

确保安装了 riscv64 工具链：
```bash
which riscv64-unknown-elf-gcc
```

### JTAG 连接失败

1. 检查 JTAG 接线
2. 降低 `adapter speed`（尝试 500 或 250）
3. 确认 FPGA 已正确烧录 bitstream

### UART 无输出

1. 确认串口波特率设置为 115200
2. 检查 TX/RX 接线
3. 确认UART 地址与 SoC 设计一致
