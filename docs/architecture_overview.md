# MyRiscV AHB-Lite 架构设计

## 概述

MyRiscV SoC 使用简化的 AHB-Lite 总线架构连接 CPU、内存和外围设备。

## 架构图

```
                         ┌──────────────────────────────────────┐
                         │           CPU Core                    │
                         │  (RV32I 5-stage pipeline)            │
                         │                                      │
                         │  ┌──────────┐    ┌──────────┐       │
                         │  │  iram_*  │    │  dbus_*  │       │
                         │  └────┬─────┘    └────┬─────┘       │
                         │       │               │              │
                         └───────┼───────────────┼──────────────┘
                                 │               │
                    ┌────────────┴───────────────┴────────────┐
                    │              CPU AHB Bridge               │
                    │  (Unified IF/Data access to AHB-Lite)   │
                    └─────────────────────┬────────────────────┘
                                          │ AHB-Lite
                    ┌─────────────────────┴────────────────────┐
                    │              AHB-Lite Bus                │
                    │         (Address Decode + MUX)          │
                    └─┬───────┬───────┬───────┬───────────────┘
                      │       │       │       │
              ┌───────┴┐  ┌───┴┐  ┌──┴──┐  ┌─┴─────────────┐
              │  IRAM  │  │DRAM│  │Flash│  │  Peripherals   │
              │ 16KB   │  │ 8KB│  │ 76KB│  │  UART/GPIO    │
              └────────┘  └────┘  └─────┘  └────────────────┘
```

## 地址映射

| 地址范围 | 大小 | 设备 | 描述 |
|----------|------|------|------|
| 0x1000_0000 - 0x1000_FFFF | 64KB | Peripherals | UART, GPIO |
| 0x2000_0000 - 0x2012_FFFF | 76KB | Flash | XIP, 复位向量 |
| 0x8000_0000 - 0x8000_3FFF | 16KB | IRAM | 指令 RAM |
| 0x8000_4000 - 0x8000_5FFF | 8KB | DRAM | 数据 RAM |

## AHB-Lite 信号

| 信号 | 宽度 | 方向 | 描述 |
|------|------|------|------|
| HADDR | 32 | Master→Bus | 地址 |
| HWDATA | 32 | Master→Bus | 写数据 |
| HRDATA | 32 | Bus→Master | 读数据 |
| HWRITE | 1 | Master→Bus | 写使能 |
| HSEL | 1 | Bus→Slave | 从设备选择 |
| HREADY | 1 | Master→Bus | 传输完成 |
| HREADYOUT | 1 | Slave→Bus | 从设备就绪 |
| HRESP | 1 | Slave→Bus | 响应 (0=OK) |
| HTRANS | 2 | Master→Bus | 传输类型 |
| HSIZE | 3 | Master→Bus | 数据大小 |
| HSTRB | 4 | Master→Bus | 字节使能 |

## 地址解码

```verilog
// 高位地址判断
wire is_sram    = (HADDR[31:28] == 4'h8);   // 0x8xxx_xxxx
wire is_flash   = (HADDR[31:28] == 4'h2);   // 0x2xxx_xxxx
wire is_periph  = (HADDR[31:28] == 4'h1);   // 0x1xxx_xxxx

// SRAM 内部
wire is_iram    = is_sram && (HADDR[14] == 1'b0);  // 0x8000_0000 - 0x8000_3FFF
wire is_dram    = is_sram && (HADDR[14] == 1'b1);  // 0x8000_4000 - 0x8000_5FFF
```

## 文件列表

### AHB-Lite 总线模块
- `rtl/soc/ahblite_bus.sv` - AHB-Lite 总线矩阵
- `rtl/soc/cpu_ahb_bridge.sv` - CPU AHB 桥接器
- `rtl/soc/ahblite_ram.sv` - RAM AHB 接口
- `rtl/soc/ahblite_flash.sv` - Flash AHB 接口
- `rtl/soc/ahblite_ram_wrapper.sv` - RAM 封装

### Cache 模块
- `rtl/soc/ahblite_icache.sv` - 2KB 直接映射 I-Cache
- `rtl/soc/ahblite_dcache.sv` - 2KB 直接映射 D-Cache (写回)

### SoC 顶层
- `rtl/soc/MyRiscV_ahb_soc.sv` - AHB-Lite 版本 SoC (新建)
- `rtl/soc/MyRiscV_soc_top.sv` - 原始简单 MUX 版本 SoC

### 内存模块
- `rtl/perips/iram.sv` - IRAM (16KB)
- `rtl/perips/dram.sv` - DRAM (8KB)
- `rtl/perips/flash_ctrl.sv` - Flash 控制器

### 外设模块
- `rtl/perips/uart.sv` - UART 控制器
- `rtl/perips/gpio.sv` - GPIO 控制器

## BSRAM 资源使用

| 组件 | SDPB 块数 | 大小 | 说明 |
|------|----------|------|------|
| IRAM | 8 | 16KB | 8 × SDPB 512×32 |
| DRAM | 4 | 8KB | 4 × SDPB 512×32 |
| RegFile | 3 | 32×32bit | 3 × SDPB |
| I-Cache (可选) | 1 | 2KB | 直接映射 |
| D-Cache (可选) | 1 | 2KB | 直接映射, 写回 |
| **总计** | **16-18** | **~28KB** | **26 BSRAM 中** |

## 复位和启动

1. CPU 复位向量: 0x20000000 (Flash)
2. Flash 第一条指令: `lui sp, 0x80006`
3. 跳转到 main 函数
4. main 调用 putchar 输出字符串

## 当前问题

仿真在输出 'H' 后超时。Flash 内容正确但 CPU 执行流程挂起。

可能原因:
1. UART STATUS 寄存器读取问题
2. CPU 流水线卡住
3. 跳转指令行为异常

## 验证状态

```bash
# 编译仿真
make clean && make sim_soc

# 预期: 输出 "Hello, World!\n" 后显示 "Simulation passed"
# 当前: 只输出 'H' 后超时
```
