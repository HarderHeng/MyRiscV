# MyRiscV

基于 RISC-V RV32I 的 5 级流水线 CPU，面向 Sipeed Tang Nano 9K (GW1NR-9) FPGA。

## 工具链

OSS CAD Suite：`yosys` + `nextpnr-gowin` + `apicula`

## 项目结构

```
MyRiscV/
├── rtl/
│   ├── alu/            # ALU 模块
│   ├── core/           # 流水线核心（IF/ID/EX/MEM/WB）
│   ├── perips/         # 外设（ROM/RAM/Timer）
│   ├── debug/          # JTAG 调试模块
│   └── soc/            # SoC 顶层
├── sim/
│   ├── tb/             # Testbench
│   └── scripts/        # 仿真脚本
├── syn/
│   ├── constraints/    # 时序约束
│   └── scripts/        # 综合脚本
├── sw/
│   ├── linker/         # 链接脚本
│   ├── startup/        # 启动代码
│   └── test/           # 测试程序
├── docs/
│   └── design_spec.md  # 设计规格说明书
└── Makefile
```

## 快速开始

```bash
# 仿真 ALU
make sim_alu

# 仿真完整核心
make sim_core

# FPGA 综合（需要 OSS CAD Suite）
make synth

# 烧录（需要 openFPGALoader）
make prog
```

## 设计文档

见 [docs/design_spec.md](docs/design_spec.md)
