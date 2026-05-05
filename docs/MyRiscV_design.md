# MyRiscV SoC 详细设计文档

**项目**: MyRiscV - 5级流水线RISC-V处理器SoC
**目标器件**: Gowin GW1NR-9C (TangNano-9K)
**CPU架构**: RV32I 5级流水线
**文档版本**: v2.0 (架构演进中)
**最后更新**: 2026-05-07

---

## 架构演进说明 (v2.0)

本项目正在从简单架构演进到类单片机架构：

**目标架构**:
- Flash + iCache: 存储可执行代码和data/bss段
- RAM + dCache: 存储运行时数据
- 遵循RISC-V启动规范，支持完整的启动流程

**当前实现**:
- 简化版本: Flash XIP + IRAM + DRAM
- Cache模块已创建 (icache.sv, dcache.sv)，待集成

---

## 目录

1. [系统概述](#1-系统概述)
2. [硬件规格](#2-硬件规格)
3. [系统架构](#3-系统架构)
4. [地址映射](#4-地址映射)
5. [时钟与复位](#5-时钟与复位)
6. [顶层模块](#6-顶层模块)
7. [CPU核心](#7-cpu核心)
8. [流水线阶段](#8-流水线阶段)
9. [总线系统](#9-总线系统)
10. [内存控制器](#10-内存控制器)
11. [外设模块](#11-外设模块)
12. [调试系统](#12-调试系统)
13. [启动流程](#13-启动流程)
14. [软件编译](#14-软件编译)
15. [仿真验证](#15-仿真验证)
16. [FPGA综合](#16-fpga综合)

---

## 1. 系统概述

### 1.1 项目简介

MyRiscV是一个基于自研5级流水线RISC-V处理器的完整SoC实现，部署于TangNano-9K开发板。集成了:

- **处理器**: RV32I 5级流水线核心
- **存储**: Flash (76KB XIP) + iCache (2KB) + RAM (8KB) + dCache (2KB)
- **通信**: UART (115200 baud)
- **调试**: JTAG-DMI接口

### 1.2 技术规格

| 参数 | 值 | 说明 |
|------|-----|------|
| 目标FPGA | GW1NR-9C | TangNano-9K (9K器件) |
| 系统时钟 | 27MHz | 外部晶振输入 |
| CPU架构 | RV32I | 32位整数指令集,无压缩指令 |
| 流水线深度 | 5级 | IF-ID-EX-MEM-WB |
| iCache | 2KB | 直接映射, 128行×16字节 |
| dCache | 2KB | 直接映射, 写直达策略 |
| 内存总量 | 100KB | IRAM 16KB + DRAM 8KB + Flash 76KB |
| UART波特率 | 115200 | 8N1格式 |

---

## 2. 硬件规格

### 2.1 TangNano-9K开发板规格

| 资源 | 规格 |
|------|------|
| FPGA芯片 | Gowin GW1NR-LV9QN88PC6/I5 |
| 逻辑单元 | 8640 LUT4 |
| 寄存器 | 6480 |
| Block RAM | 60Kbits |
| 用户IO | 44个 |
| 封装 | QFN88 |
| 电压 | 3.3V/1.8V |
| 外部时钟 | 27MHz晶振 |

### 2.2 板级资源分布

```
TangNano-9K 布局:
┌─────────────────────────────────┐
│  USB-C (供电+UART)             │
│  [FTDI FT232R USB-UART]        │
│                                 │
│  ┌─────────────────────────┐   │
│  │    GW1NR-9C FPGA        │   │
│  │    ┌───────────────┐    │   │
│  │    │  27MHz晶振   │    │   │
│  │    └───────────────┘    │   │
│  └─────────────────────────┘   │
│                                 │
│  [LED0-5]  [KEY]  [RGB]       │
│                                 │
│  IO Bank:                       │
│  - PIO0-10: 1.8V (Bank 2)     │
│  - PIO11-21: 3.3V (Bank 1)    │
│  - PIO22-33: 3.3V (Bank 0)    │
│  - PIO34-43: 3.3V (Bank 3)    │
└─────────────────────────────────┘
```

---

## 3. 系统架构

### 3.1 整体架构图

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              MyRiscV_soc_top                                    │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                            CpuCore (RISC-V 5级流水线)                       │ │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐          │ │
│  │  │   IF    │→│   ID    │→│   EX    │→│   MEM   │→│   WB    │          │ │
│  │  │  取指   │  │  译码   │  │  执行   │  │  访存   │  │  写回   │          │ │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘  └─────────┘          │ │
│  │       │            │            │            │                               │ │
│  │       ▼            ▼            ▼            ▼                               │ │
│  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐                            │ │
│  │  │RegFile │  │  ALU   │  │ Hazard │  │Forward │                            │ │
│  │  │  32x32 │  │        │  │ 检测   │  │ 单元   │                            │ │
│  │  └────────┘  └────────┘  └────────┘  └────────┘                            │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                     │                                            │
│         ┌───────────────────────────┼───────────────────────────────┐          │
│         │ I-BUS                    │ D-BUS                          │          │
│         ▼                           ▼                                ▼          │
│  ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐           │
│  │      IRAM        │     │      IRAM       │     │      UART       │           │
│  │    0x8000_0000   │     │    0x8000_0000   │     │   0x1000_0000   │           │
│  │   (I-BUS只读)    │     │   (D-BUS读写)    │     │                 │           │
│  └────────┬─────────┘     └────────┬─────────┘     └──────────────────┘           │
│           │                        │                                            │
│           │                        │                                            │
│           ▼                        ▼                                            │
│  ┌──────────────────┐     ┌──────────────────┐                                    │
│  │     Flash       │     │      DRAM       │      ┌──────────────────┐           │
│  │   0x2000_0000   │     │   0x8000_4000   │      │   DebugModule   │           │
│  │   (XIP只读)     │     │    (读写)       │      │   + JtagDTM     │           │
│  └──────────────────┘     └──────────────────┘      └────────┬─────────┘           │
│                                                              │                    │
│                     ┌────────────────────────────────────────┘                    │
│                     ▼                                                               │
│              ┌─────────────────┐                                                   │
│              │   AHBLiteBus    │                                                   │
│              │  (I-BUS/D-BUS/  │                                                   │
│              │     SBA MUX)     │                                                   │
│              └────────┬────────┘                                                   │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 模块层次

```
MyRiscV_soc_top (顶层)
├── CpuCore (CPU核心 - AHBLite Master)
│   ├── InstructionFetch (IF - 取指)
│   │   └── PC寄存器
│   ├── IFID (IF/ID流水线寄存器)
│   ├── InstructionDecode (ID - 译码)
│   │   ├── 控制信号生成
│   │   ├── 立即数扩展
│   │   └── 跳转目标计算
│   ├── IDEX (ID/EX流水线寄存器)
│   ├── Execute (EX - 执行)
│   │   ├── ALU (算术逻辑单元)
│   │   └── 分支比较器
│   ├── EXMEM (EX/MEM流水线寄存器)
│   ├── Memory (MEM - 访存)
│   │   └── 加载存储单元
│   ├── MEMWB (MEM/WB流水线寄存器)
│   ├── RegFile (寄存器堆 32x32)
│   ├── HazardUnit (冒险检测)
│   └── ForwardUnit (前推单元)
├── AHBLiteBus (AHBLite总线矩阵)
│   ├── I-BUS MUX (取指地址选择)
│   ├── D-BUS MUX (访存地址选择)
│   └── SBA MUX (系统总线访问)
├── IRAM (指令存储器 16KB - 双端口AHBLite Slave)
├── DRAM (数据存储器 8KB - AHBLite Slave)
├── FlashCtrl (Flash控制器 76KB - AHBLite Slave, XIP)
├── UART (通用异步收发器 - AHBLite Slave)
├── JtagDTM (JTAG调试传输模块)
└── DebugModule (调试模块 - SBA, halt/resume)
```

---

## 4. 地址映射

### 4.1 I-BUS 地址空间 (取指)

| 地址范围 | 大小 | 设备 | 说明 |
|----------|------|------|------|
| 0x2000_0000 - 0x2012_FFFF | 76KB | Flash | XIP启动存储器 (只读) |
| 0x8000_0000 - 0x8000_3FFF | 16KB | IRAM | 指令存储器 (只读) |

### 4.2 D-BUS 地址空间 (访存)

| 地址范围 | 大小 | 设备 | 说明 |
|----------|------|------|------|
| 0x1000_0000 - 0x1000_FFFF | 64KB | 外设 | UART |
| 0x2000_0000 - 0x2012_FFFF | 76KB | Flash | XIP启动存储器 (只读) |
| 0x8000_0000 - 0x8000_3FFF | 16KB | IRAM | 数据存取 (读写) |
| 0x8000_4000 - 0x8000_5FFF | 8KB | DRAM | 数据存储器 (读写) |

### 4.3 外设地址映射

| 地址 | 寄存器 | 说明 |
|------|--------|------|
| 0x1000_0000 | TXDATA | UART发送数据 |
| 0x1000_0004 | RXDATA | UART接收数据 |
| 0x1000_0008 | STATUS | UART状态寄存器 |
| 0x1000_000C | DIVISOR | 波特率分频 |

---

## 5. 时钟与复位

### 5.1 时钟架构

```
外部晶振 27MHz
      │
      ▼
┌─────────────┐
│  FPGA时钟   │  ← 直接使用27MHz不经过PLL
│  输入clk    │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────┐
│           CpuCore / 各模块              │
│         (统一27MHz时钟驱动)             │
└─────────────────────────────────────────┘
```

### 5.2 复位架构

- **复位类型**: 高有效同步复位
- **复位信号**: rst_n (外部按键, 低有效 → 内部 rst)
- **复位时长**: 100ns以上
- **复位后PC**: 0x2000_0000 (Flash启动地址)

---

## 6. 顶层模块

### 6.1 MyRiscV_soc_top

**文件**: `rtl/soc/MyRiscV_soc_top.sv`

**端口定义**:

| 端口名 | 方向 | 位宽 | 说明 |
|--------|------|------|------|
| clk | input | 1 | 系统时钟 27MHz |
| rst_n | input | 1 | 复位信号, 低有效 |
| uart_tx | output | 1 | UART发送 |
| uart_rx | input | 1 | UART接收 |
| jtag_tck | input | 1 | JTAG时钟 |
| jtag_tms | input | 1 | JTAG模式选择 |
| jtag_tdi | input | 1 | JTAG数据输入 |
| jtag_tdo | output | 1 | JTAG数据输出 |
| jtag_trst_n | input | 1 | JTAG复位 |
| gpio_out | output | 32 | GPIO输出 |
| gpio_in | input | 32 | GPIO输入 |
| led | output | 6 | LED输出 |

**子模块例化**:

```verilog
CpuCore    u_cpu    (.clk, .rst, ...);
IRAM        u_iram   (.clk, ...);
DRAM        u_dram   (.clk, ...);
FlashCtrl   u_flash  (.clk, .rst, ...);
UART        u_uart   (.clk, .rst, ...);
simple_bus  u_bus    (...);
```

---

## 7. CPU核心

### 7.1 CpuCore

**文件**: `rtl/core/cpu_core.sv`

**功能**: 5级流水线RISC-V处理器核心顶层

**流水线阶段**:

```
Cycle 1: IF  → ID  → EX  → MEM → WB
Cycle 2:     IF  → ID  → EX  → MEM → WB
Cycle 3:         IF  → ID  → EX  → MEM → WB
```

**支持指令类型**:
- R型: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
- I型: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
- Load: LB, LH, LW, LBU, LHU
- Store: SB, SH, SW
- 分支: BEQ, BNE, BLT, BGE, BLTU, BGEU
- 跳转: JAL, JALR
- LUI, AUIPC
- SYSTEM: ECALL, EBREAK (当NOP处理)

**冒险处理**:
- Load-Use冒险: 插入1周期stall
- 分支冒险: flush无效指令
- 数据前推: EX/MEM阶段结果前推到ID

---

## 8. 流水线阶段

### 8.1 IF - InstructionFetch (取指)

**文件**: `rtl/core/if.sv`

**功能**:
- PC寄存器维护
- 指令读取地址输出

**接口信号**:

| 信号 | 方向 | 说明 |
|------|------|------|
| clk | input | 时钟 |
| rst | input | 复位 |
| jmp | input | 跳转信号 |
| jmp_addr | input[31:0] | 跳转目标地址 |
| hold | input | 暂停信号 |
| pc | output[31:0] | 当前PC |

**PC更新逻辑**:
```
优先级: rst > hold > jmp > pc+4
- 复位: pc = 0x20000000
- 暂停: pc = pc (保持)
- 跳转: pc = jmp_addr
- 正常: pc = pc + 4
```

### 8.2 ID - InstructionDecode (译码)

**文件**: `rtl/core/id.sv`

**功能**:
- 指令译码
- 控制信号生成
- 立即数扩展
- 跳转目标计算

**opcode映射**:

| opcode[6:0] | 指令类型 |
|-------------|----------|
| 0110011 | R型 (reg-reg) |
| 0010011 | I型 (reg-imm) |
| 0000011 | Load |
| 0100011 | Store |
| 1100011 | Branch |
| 1101111 | JAL |
| 1100111 | JALR |
| 0110111 | LUI |
| 0010111 | AUIPC |
| 1110011 | SYSTEM |

### 8.3 EX - Execute (执行)

**文件**: `rtl/core/ex.sv`

**功能**:
- ALU运算
- 分支条件判断
- 跳转目标输出

**ALU操作**:

| alu_op | 操作 |
|--------|------|
| 0000 | ADD |
| 0001 | SUB |
| 0010 | SLL |
| 0011 | SLT |
| 0100 | SLTU |
| 0101 | XOR |
| 0110 | SRL |
| 0111 | SRA |
| 1000 | OR |
| 1001 | AND |
| 1110 | COPY_A (pc+4) |
| 1111 | COPY_B (imm) |

### 8.4 MEM - Memory (访存)

**文件**: `rtl/core/mem.sv`

**功能**:
- 加载/存储操作
- 字节使能生成

**访存粒度**:

| funct3[2:0] | 操作 | 字节数 |
|--------------|------|--------|
| 000 | LB | 1 |
| 001 | LH | 2 |
| 010 | LW | 4 |
| 100 | LBU | 1 (零扩展) |
| 101 | LHU | 2 (零扩展) |
| 000 | SB | 1 |
| 001 | SH | 2 |
| 010 | SW | 4 |

### 8.5 WB - WriteBack (写回)

**功能**: 将执行结果写回寄存器堆

**写回来源优先级**:
1. MEM阶段加载数据
2. EX阶段ALU结果

---

## 9. 总线系统

### 9.1 AHBLiteBus

**文件**: `rtl/soc/ahblite_bus.sv`

**功能**: AHB-Lite 总线矩阵，支持三组端口：
- I-BUS Master (CPU 取指)
- D-BUS Master (CPU 访存)
- SBA (Debug Module 系统总线访问)

**地址解码**:

**I-BUS (取指)**:
| 地址范围 | 选择信号 | 设备 |
|----------|----------|------|
| 0x8000_xxxx | sel_iram | IRAM |
| 0x2xxx_xxxx | sel_flash | Flash |

**D-BUS (访存)**:
| 地址范围 | 选择信号 | 设备 |
|----------|----------|------|
| 0x8000_0000-3FFF | sel_iram | IRAM |
| 0x8000_4000-5FFF | sel_dram | DRAM |
| 0x2xxx_xxxx | sel_flash | Flash |
| 0x1xxx_xxxx | sel_uart | UART |

**SBA (系统总线访问)**:
| 地址范围 | 设备 |
|----------|------|
| 0x8000_xxxx | IRAM |
| 0x8000_4000-5FFF | DRAM |

**优先级**: SBA > CPU D-BUS > CPU I-BUS

---

## 10. 内存控制器

### 10.1 IRAM (指令存储器)

**文件**: `rtl/perips/iram.sv`

**规格**:
- 容量: 16KB (4096 × 32bit)
- 地址: 0x8000_0000 - 0x8000_3FFF
- word索引: addr[13:2]

**端口**:
- 指令端口: 同步读
- 数据端口: 同步读写, 字节使能
- 调试端口: 同步读写

**综合实现**: 8 × Gowin SDPB (BRAM原语)

### 10.2 DRAM (数据存储器)

**文件**: `rtl/perips/dram.sv`

**规格**:
- 容量: 8KB (2048 × 32bit)
- 地址: 0x8000_4000 - 0x8000_5FFF
- word索引: addr[12:2]

**端口**: 数据端口 + 调试端口

**综合实现**: 4 × Gowin SDPB

### 10.3 FlashCtrl (Flash控制器)

**文件**: `rtl/perips/flash_ctrl.sv`

**规格**:
- 容量: 76KB (19648 × 32bit)
- 地址: 0x2000_0000 - 0x2012_FFFF
- 支持: XIP (Execute-In-Place)

**端口**:
- CPU数据端口: 同步读
- 指令端口: XIP同步读

**仿真实现**: $readmemh行为模型
**综合实现**: FLASH608K原语例化

---

## 11. 外设模块

### 11.1 UART

**文件**: `rtl/perips/uart.sv`

**规格**:
- 波特率: 115200 bps
- 数据位: 8
- 停止位: 1
- 校验: 无

**寄存器**:

| 偏移 | 名称 | 说明 |
|------|------|------|
| 0x00 | TXDATA | 发送数据寄存器 |
| 0x04 | RXDATA | 接收数据寄存器 |
| 0x08 | STATUS | 状态寄存器 [0]=TX忙, [1]=RX有数据 |
| 0x0C | DIVISOR | 波特率分频 (默认234) |

**时序参数** (27MHz时钟):
- 波特周期: 234 × (1/27MHz) = 8.67μs
- 位采样: 16倍过采样

### 11.2 GPIO

**文件**: `rtl/perips/gpio.sv`

**规格**:
- 位宽: 32位
- 地址: 0x1000_1000

**功能**: 通用输入输出控制

---

## 12. 调试系统

### 12.1 JTAG_DTM

**文件**: `rtl/debug/jtag_dtm.sv`

**功能**: JTAG调试传输模块

**符合规范**: RISC-V Debug Spec v0.13.2

### 12.2 DebugModule

**文件**: `rtl/debug/debug_module.sv`

**功能**: 处理器调试控制

**调试接口**:
- halt/resume请求
- 寄存器读写
- PC读取
- 内存访问 (SBA - System Bus Access)

---

## 13. 启动流程

### 13.1 上电复位

```
1. 复位释放 (rst_n = 1)
2. PC = 0x20000000 (Flash起始)
3. 取指 → 译码 → 执行
4. 加载程序到IRAM/DRAM
5. 跳转到main()
```

### 13.2 Flash启动程序

```assembly
_start:
    lui sp, 0x80006        ; 设置栈指针
    jal main               ; 跳转到main
halt_loop:
    j halt_loop            ; 死循环

main:
    ; 初始化
    addi sp, sp, -16
    sw ra, 12(sp)
    ; 输出字符串
    la t0, hello_str
putchar_loop:
    lbu t1, 0(t0)
    beq t1, zero, putchar_done
    ; 等待TX就绪
    lw t3, UART_STATUS
    andi t3, t3, 1
    bne t3, zero, wait_tx_ready
    ; 发送字符
    sw t1, UART_TX
    addi t0, t0, 1
    j putchar_loop
putchar_done:
    lw ra, 12(sp)
    addi sp, sp, 16
    ret
```

---

## 14. 软件编译

### 14.1 工具链

- GCC: riscv64-unknown-elf-gcc
- 架构: rv32i
- ABI: ilp32

### 14.2 编译命令

```bash
cd sw/helloworld
RISCV_PREFIX=riscv64-unknown-elf-
CC="${RISCV_PREFIX}gcc"
OBJCOPY="${RISCV_PREFIX}objcopy"

${CC} -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding \
      -T link.ld -o helloworld.elf helloworld.s
${OBJCOPY} -O binary helloworld.elf helloworld.bin
```

### 14.3 链接脚本

```ld
MEMORY {
    FLASH (rx) : ORIGIN = 0x20000000, LENGTH = 76K
    DRAM  (rwx): ORIGIN = 0x80004000, LENGTH = 8K
}

SECTIONS {
    .text : { *(.text) } > FLASH
    .rodata : { *(.rodata) } > FLASH
    .data : { _data_start = .; *(.data) } > DRAM AT > FLASH
    .bss : { _bss_start = .; *(.bss) } > DRAM
    _stack_top = ORIGIN(DRAM) + LENGTH(DRAM);
}
```

---

## 15. 仿真验证

### 15.1 仿真命令

```bash
make sim_soc
```

### 15.2 预期输出

```
=== Running SoC simulation ===
[INFO] tb_soc started. Clock=27MHz, UART=115200bps
[UART TX WRITE] data=0x48 'H' at time xxx ns, PC=0x20000000
[UART TX WRITE] data=0x65 'e' at time xxx ns, PC=0x20000048
...
[UART TX WRITE] data=0x21 '!' at time xxx ns, PC=0x20000048
[UART TX WRITE] data=0x0a '\n' at time xxx ns, PC=0x20000048
Simulation completed successfully
```

### 15.3 验证点

- [x] CPU正确执行helloworld程序
- [x] UART正确发送 "Hello, World!\n"
- [x] 分支跳转正确 (jal main)
- [x] 内存读写正确
- [x] 波特率正确 (115200 bps)

---

## 16. FPGA综合

### 16.1 综合命令

```bash
make synth      # Yosys综合
make pnr        # nextpnr布局布线
make bitstream  # 生成比特流
make prog       # 烧录到板子
```

### 16.2 器件配置

```bash
Device: GW1NR-LV9QN88PC6/I5
Package: QFN88
Speed grade: C6
```

### 16.3 约束文件

**文件**: `syn/constraints/myriscv.pcf`

```
# 时钟约束
set_io clk 52

# UART
set_io uart_tx 1
set_io uart_rx 4

# LED
set_io led[0] 10
set_io led[1] 11
...
```

---

## 附录: 信号列表

### A.1 CPU核心信号

| 信号名 | 方向 | 位宽 | 说明 |
|--------|------|------|------|
| clk | input | 1 | 系统时钟 |
| rst | input | 1 | 同步复位 |
| iram_addr | output | 32 | IRAM地址 |
| iram_rdata | input | 32 | IRAM数据 |
| dbus_addr | output | 32 | 数据总线地址 |
| dbus_ren | output | 1 | 数据读使能 |
| dbus_wen | output | 1 | 数据写使能 |
| dbus_be | output | 4 | 字节使能 |
| dbus_wdata | output | 32 | 数据写入值 |
| dbus_rdata | input | 32 | 数据读取值 |

### A.2 SoC顶层信号

| 信号名 | 方向 | 位宽 | 说明 |
|--------|------|------|------|
| clk | input | 1 | 27MHz时钟 |
| rst_n | input | 1 | 低有效复位 |
| uart_tx | output | 1 | UART发送 |
| uart_rx | input | 1 | UART接收 |
| led | output | 6 | LED输出 |

---

## 版本历史

| 版本 | 日期 | 修改内容 |
|------|------|----------|
| v1.0 | 2026-05-06 | 初始版本 |

