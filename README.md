# MyRiscV

基于 RISC-V RV32I 的 5 级流水线 CPU SoC，面向 Sipeed Tang Nano 9K (GW1NR-9C) FPGA。

## 特性

- **CPU**：RV32I 5 级流水线（IF/ID/EX/MEM/WB），含前递、load-use stall、分支冲刷
- **BSRAM**：直接例化 Gowin SDPB 原语（IRAM 8块×2KB=16KB，DRAM 4块×2KB=8KB）
- **Flash**：片上 FLASH608K（76KB 用户区，0x20000000），FlashCtrl 2状态机读取
- **UART**：8N1 115200bps，轮询，调试串口输出
- **调试**：JTAG DTM + Debug Module（RISC-V Debug Spec v0.13.2），兼容 OpenOCD/GDB
- **仿真**：iverilog + vvp，testbench 解码 UART 波形验证 "Hello!\n" 输出

## 工具链

```bash
source /home/heng/oss-cad-suite/environment
```

OSS CAD Suite：`iverilog` + `yosys` + `nextpnr-gowin` + `apicula`

## 快速开始

```bash
# ALU 单元测试（36 项）
make sim_alu

# SoC 系统仿真（验证 UART 输出 "Hello!\n"）
make sim_soc

# 生成 SDPB INIT_RAM 参数
python3 tools/mem2init.py rtl/perips/iram_init.mem

# FPGA 综合（加 -DSYNTHESIS 启用 SDPB/FLASH608K 原语）
make synth

# 布局布线
make pnr

# 生成比特流
make bitstream

# 烧录到 Tang Nano 9K
make prog
```

## 地址映射

| 地址范围                   | 模块         | 大小   |
|----------------------------|--------------|--------|
| `0x80000000 ~ 0x80003FFF` | IRAM         | 16 KB  |
| `0x80004000 ~ 0x80005FFF` | DRAM         | 8 KB   |
| `0x10000000 ~ 0x1000001F` | UART         | 32 B   |
| `0x20000000 ~ 0x20012FFF` | 片上 Flash   | 76 KB  |

## 项目结构

```
MyRiscV/
├── rtl/
│   ├── alu/            # ALU 模块（RvALU，避免与 Gowin 原语冲突）
│   ├── core/           # 流水线核心（IF/ID/EX/MEM/WB + HazardUnit）
│   ├── perips/         # 外设（IRAM/DRAM/FlashCtrl/UART）
│   ├── debug/          # JTAG DTM + Debug Module
│   └── soc/            # SoC 顶层
├── sim/tb/             # Testbench（tb_alu.sv / tb_soc.sv）
├── syn/constraints/    # 引脚约束（myriscv.pcf）
├── sw/                 # 交叉编译软件（链接脚本/启动代码/测试程序）
├── tools/              # 辅助工具（mem2init.py）
├── docs/
│   └── design_spec.md  # 详细设计规格说明书（v0.4）
└── Makefile
```

## 开发状态

- **Phase 1**（完成）：CPU 核 + 仿真验证，UART 输出 "Hello!\n" ✓
- **Phase 2**（仿真完成，综合进行中）：SDPB 直接例化 + FlashCtrl + iram_wait 适配
- **Phase 3**（待开始）：Flash 写/擦除 + MCU 烧录流程
- **Phase 4**（规划中）：CLINT Timer + CSR + 软件中断

## 设计文档

见 [docs/design_spec.md](docs/design_spec.md)
