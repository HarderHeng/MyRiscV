# MyRiscV SoC 设计规格说明书

> 版本：v0.2 | 更新时间：2026-03-18

---

## 1. 项目概述

在 Sipeed Tang Nano 9K（GW1NR-9C）FPGA 上实现一个完整可调试的 RISC-V RV32I SoC：

| 项目         | 说明                                                    |
|--------------|---------------------------------------------------------|
| 目标器件     | Gowin GW1NR-9C（LittleBee 系列，88-pin QFN）           |
| 工具链       | OSS CAD Suite（Yosys + nextpnr-gowin + apicula）        |
| 指令集       | RISC-V RV32I 基础整数指令集（37 条指令，全部实现）      |
| 流水线       | 经典 5 级（IF → ID → EX → MEM → WB）                  |
| 主频目标     | 27 MHz（板载晶振直驱，后期可 PLL 至 50 MHz）            |
| 调试接口     | RISC-V Debug Specification v0.13.2（标准 JTAG DTM+DM） |
| 调试工具     | OpenOCD + GDB（标准 RISC-V 调试工具链）                 |
| 调试功能     | halt/resume、寄存器读写、内存读写、单步、断点           |

---

## 2. 明确需求（Confirmed Requirements）

### 2.1 CPU Core

- **指令集**：RV32I，全部 37 条指令，无例外
- **流水线**：5 级经典流水线，哈佛架构（指令/数据分离总线）
- **冒险处理**：
  - 数据冒险：EX→ID 和 MEM→ID 两级前递（Forwarding）
  - Load-use：插入 1 个气泡（stall）
  - 控制冒险：EX 阶段判断跳转，冲刷 2 个气泡（flush）
- **复位**：同步高有效，复位地址 `0x80000000`

### 2.2 JTAG 调试（核心需求）

> **JTAG 必须遵循 RISC-V Debug Specification v0.13.2**，能直接被 `riscv-openocd` 连接，支持：
> - halt / resume CPU
> - 读写所有通用寄存器（x0~x31）
> - 读写内存（System Bus Access）
> - 单步执行（step）
> - 硬件断点（可选，Phase 2）
> - 标准 GDB 调试流程（`target remote`）

**JTAG 组件：**
- **DTM**（Debug Transport Module）：标准 IEEE 1149.1 TAP，支持 IDCODE / DTMCS / DMI 三个 DR
- **DM**（Debug Module）：符合 Debug Spec，实现所有必要 DMI 寄存器
- **TCK 跨时钟域**：TCK 域与系统时钟域正确同步（toggle + 2FF 方案）

### 2.3 存储器

- **IRAM（16 KB，BSRAM×8）**：CPU 运行内存，上电时预置测试程序或引导代码
- **DRAM（8 KB，BSRAM×4）**：数据/栈
- **片上 NOR Flash（76 KB，内置）**：Phase 3 实现，目前暂不使用
- **仿真 SimRAM**：IRAM+DRAM 合一（32 KB），`initial` 块写死测试程序，用于功能验证

### 2.4 UART（调试串口）

- 8N1，115200 bps，轮询方式（无中断），TX+RX 均实现
- 用于调试输出（`printf`），不依赖 JTAG
- 分频系数：27 MHz ÷ 115200 = 234

### 2.5 功能验证方案

- 将 RV32I 机器码**硬编码**在 SimRAM 的 `initial` 块中
- 程序功能：输出 `"Hello!\n"` 到 UART TX
- 仿真 testbench（`tb_soc.sv`）：解码 UART TX 波形，接收到 `'\n'` 后打印 `Simulation passed`
- 验证通过后再进行 FPGA 综合

---

## 3. 系统架构

### 3.1 SoC 顶层框图

```
╔══════════════════════════════════════════════════════════════════════╗
║                         MyRiscV SoC Top                             ║
║                                                                      ║
║  ┌────────────────────────────────────────────────────────────────┐  ║
║  │                   RISC-V Core（5 级流水线）                    │  ║
║  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐   │  ║
║  │  │ IF  │→│IF/ID│→│ ID  │→│ID/EX│→│ EX  │→│EX/ME│→│ MEM │   │  ║
║  │  └─────┘ └─────┘ └──┬──┘ └─────┘ └──┬──┘ └─────┘ └──┬──┘   │  ║
║  │              前递←──┘        前递←──┘         前递←──┘       │  ║
║  │  ┌────────────────┐  ┌──────────────┐                          │  ║
║  │  │  RegFile 32×32 │  │  HazardUnit  │                          │  ║
║  │  └────────────────┘  └──────────────┘                          │  ║
║  └──────────────────────────────┬───────────────────────────────┘  ║
║                                 │ 数据总线（地址译码）               ║
║  ┌──────────┐  ┌───────────┐   │   ┌────────────┐  ┌───────────┐  ║
║  │  IRAM    │  │  DRAM     │◄──┤   │    UART    │  │  Flash    │  ║
║  │  16KB    │  │  8KB      │   │   │  0x1000... │  │  Ctrl     │  ║
║  │ BSRAM×8  │  │ BSRAM×4   │   │   └────────────┘  │(Phase 3)  │  ║
║  └──────────┘  └───────────┘   │                   └───────────┘  ║
║                                 │                                    ║
║  ┌──────────────────────────────┴─────────────────────────────────┐ ║
║  │                  RISC-V Debug（Debug Spec v0.13.2）             │ ║
║  │   ┌────────────────────────┐   ┌────────────────────────────┐  │ ║
║  │   │     JTAG DTM           │   │     Debug Module (DM)      │  │ ║
║  │   │  (IEEE 1149.1 TAP)     │←→│  DMI 寄存器 + SBA          │  │ ║
║  │   │  IR: IDCODE/DTMCS/DMI │   │  Abstract Command          │  │ ║
║  │   │  跨时钟域: toggle+2FF  │   │  halt/resume/step/break    │  │ ║
║  │   └────────────────────────┘   └────────────────────────────┘  │ ║
║  └────────────────────────────────────────────────────────────────┘ ║
╚══════════════════════════════════════════════════════════════════════╝
```

### 3.2 地址空间映射

| 地址范围                        | 大小   | 模块             | FPGA 资源           | 阶段    |
|---------------------------------|--------|------------------|---------------------|---------|
| `0x80000000 ~ 0x80003FFF`      | 16 KB  | IRAM             | BSRAM × 8（推断）   | Phase 1 |
| `0x80004000 ~ 0x80005FFF`      | 8 KB   | DRAM             | BSRAM × 4（推断）   | Phase 1 |
| `0x10000000 ~ 0x1000001F`      | 32 B   | UART             | FF                  | Phase 1 |
| `0x20000000 ~ 0x20012FFF`      | 76 KB  | 片上 NOR Flash   | GW1NR 内置          | Phase 3 |
| `0x02000000 ~ 0x0200BFFF`      | 48 KB  | CLINT / Timer    | FF                  | Phase 4 |

> **CPU 复位向量**：`0x80000000`（IRAM 起始地址）

### 3.3 总线结构（简单地址译码）

```
CPU MEM 阶段输出
  └─→ {dbus_addr, dbus_ren, dbus_wen, dbus_be[3:0], dbus_wdata}
            │
    ┌───────┼────────────┬──────────────┐
    ▼       ▼            ▼              ▼
  IRAM    DRAM         UART           其他
  sel     sel          sel        rdata=32'h0
    │       │            │
    └───────┴────────────┘
                │
          dbus_rdata MUX（组合选择）
                │
    CPU MEM 阶段输入（dbus_rdata）
```

---

## 4. JTAG 调试系统详细设计

> 严格遵循 **RISC-V Debug Specification v0.13.2**

### 4.1 组件结构

```
外部调试器（OpenOCD/GDB）
        │
        │ USB-JTAG（如 FT2232H / CMSIS-DAP）
        ▼
  TCK / TMS / TDI / TDO / TRST_N
        │
  ┌─────┴────────────────────┐
  │     JTAG DTM              │  TCK 时钟域
  │   IEEE 1149.1 TAP         │
  │   IR 5位：IDCODE/DTMCS/DMI│
  │   DMI shift register 41位 │
  │   跨时钟域：toggle + 2FF  │
  └─────┬────────────────────┘
        │ DMI 总线（系统时钟域）
        │ {addr[6:0], data[31:0], op[1:0]}
        ▼
  ┌────────────────────────────────────────────┐
  │            Debug Module (DM)                │  系统时钟域
  │                                             │
  │  DMI 寄存器（参考 Debug Spec 表 3.1）：     │
  │  0x04 data0       0x10 dmcontrol            │
  │  0x11 dmstatus    0x16 abstractcs           │
  │  0x17 command     0x20 progbuf0             │
  │  0x21 progbuf1    0x38 sbcs                 │
  │  0x39 sbaddress0  0x3C sbdata0              │
  │                                             │
  │  功能：halt/resume/step/reg-rw/mem-rw       │
  └──────────┬────────────────────────┬─────────┘
             │                        │
    ┌────────┴────────┐      ┌────────┴────────┐
    │  CPU 调试接口   │      │  System Bus     │
    │ halt_req        │      │  Access (SBA)   │
    │ resume_req      │      │  直接读写总线   │
    │ reg_rw（抽象命令）│     │  (绕过 CPU)     │
    └─────────────────┘      └─────────────────┘
```

### 4.2 DTM：JTAG IR 定义（5 位）

| IR 值  | 名称    | DR 宽度 | 说明                              |
|--------|---------|---------|-----------------------------------|
| `5'h01`| IDCODE  | 32 bit  | 制造商 ID（bit[0]=1 为标准要求）   |
| `5'h10`| DTMCS   | 32 bit  | DTM 控制与状态                    |
| `5'h11`| DMI     | 41 bit  | `{addr[6:0], data[31:0], op[1:0]}`|
| `5'h1F`| BYPASS  | 1 bit   | 标准旁路                          |
| 其他   | BYPASS  | 1 bit   | 默认旁路                          |

### 4.3 DTM：DTMCS 寄存器（0x10）

| 位域    | 字段           | 说明                                        |
|---------|----------------|---------------------------------------------|
| [31:18] | 保留           | 0                                           |
| [17]    | `dmihardreset` | W=1：硬复位 DMI（清所有挂起操作）           |
| [16]    | `dmireset`     | W=1：清除 dmistat 错误状态                  |
| [12:10] | `idle`         | =1：建议在 Run-Test/Idle 保持 1 个周期      |
| [9:8]   | `dmistat`      | 0=无错，2=操作失败，3=DMI busy              |
| [7:4]   | `abits`        | =7（DMI 地址 7 位）                         |
| [3:0]   | `version`      | =1（对应 Debug Spec v0.13）                 |

### 4.4 DM：实现的 DMI 寄存器（参考 Debug Spec §3）

| 地址   | 寄存器名      | 访问  | 关键字段                                      |
|--------|---------------|-------|-----------------------------------------------|
| `0x04` | `data0`       | R/W   | 抽象命令数据寄存器 0                          |
| `0x10` | `dmcontrol`   | R/W   | [31]haltreq, [30]resumereq, [1]ndmreset, [0]dmactive |
| `0x11` | `dmstatus`    | R     | [13]allrunning, [11]allhalted, [9]authenticated=1, [3:0]version=2 |
| `0x12` | `hartinfo`    | R     | 返回 0                                       |
| `0x16` | `abstractcs`  | R/W   | [28:24]progbufsize=2, [12]busy, [10:8]cmderr（W1C）, [3:0]datacount=1 |
| `0x17` | `command`     | W     | [31:24]cmdtype=0（Access Register）          |
| `0x18` | `abstractauto`| R/W   | 暂时返回 0                                   |
| `0x1D` | `nextdm`      | R     | 返回 0（单 DM）                               |
| `0x20` | `progbuf0`    | R/W   | 程序缓冲区 0（默认 NOP）                     |
| `0x21` | `progbuf1`    | R/W   | 程序缓冲区 1（默认 EBREAK）                  |
| `0x38` | `sbcs`        | R/W   | [29:27]sbversion=1, [11:5]sbasize=32, [2]sbaccess32=1 |
| `0x39` | `sbaddress0`  | R/W   | System Bus 地址                              |
| `0x3C` | `sbdata0`     | R/W   | System Bus 数据                              |

### 4.5 Abstract Command（cmdtype=0，Access Register）

```
command[31:24] = 0       : 必须，否则 cmderr=2
command[22:20] = aarsize : 必须=2（32-bit），否则 cmderr=2
command[18]    = postexec: 执行 progbuf（MVP 中忽略）
command[17]    = transfer : 1=执行寄存器传输
command[16]    = write   : 1=写寄存器（DM→CPU），0=读寄存器（CPU→DM）
command[15:0]  = regno   : 0x1000+n=GPR[n]，0x1020=PC
```

执行条件：CPU 必须已 halt，否则 cmderr=4。

### 4.6 跨时钟域方案

```
TCK 域                          系统时钟域
─────────────────────────────────────────────────────
  UPDATE_DR (DMI)
    → 锁存 {addr, data, op}
    → toggle dmi_req_tck_tog    ──[2-FF同步]──→ dmi_req_sync[1:0]
                                              edge detect → dmi_req_pulse
                                              → 触发 DM 执行
                                              → DM 完成后更新 dmi_rdata/resp

CAPTURE_DR (DMI)                dmi_ack ──→（直接，TCK远慢于CLK，无需同步）
    ← 读 {addr, dmi_rdata_tck, dmistat}
    （dmi_rdata_tck 在 dmi_ack 时更新，
      TCK 下次 Capture 时已远超过建立时间）
```

---

## 5. 存储器设计

### 5.1 BSRAM 资源分配（GW1NR-9C，共 26 块 × 18Kbit）

| 用途         | 块数 | 容量  | 配置模式   | 实现方式          |
|--------------|------|-------|------------|-------------------|
| IRAM（指令） | 8    | 16 KB | 36×512 ×8 | Yosys 自动推断    |
| DRAM（数据） | 4    | 8 KB  | 36×512 ×4 | Yosys 自动推断    |
| RegFile      | 1~2  | 2~4 KB| 36×32 ×1  | Yosys 自动推断    |
| 预留         | 12   | 24 KB | -          | 后期扩展          |

> **Yosys 推断**：使用 `reg [31:0] mem[0:N-1]` + `synth_gowin -bsram`，
> 综合器自动选用 BSRAM 原语，无需手动例化。

### 5.2 仿真 SimRAM（验证阶段使用）

- 32 KB，IRAM + DRAM 合一
- `initial` 块硬编码测试程序（输出 "Hello!\n"）
- 三端口：指令只读 + 数据读写 + 调试读写
- 调试端口供 DM System Bus Access 使用

### 5.3 IRAM 初始化（FPGA 部署时）

```
方案A（简化）：上电后 CPU 直接从 IRAM 运行，IRAM 通过比特流预置（.mem 文件）
方案B（完整）：上电后运行 Flash 中的引导代码，将程序从 Flash 复制到 IRAM
```

---

## 6. UART 设计

| 参数       | 值                          |
|------------|-----------------------------|
| 格式       | 8N1（8位数据，无校验，1停止位）|
| 波特率     | 115200 bps                  |
| 分频系数   | 27,000,000 ÷ 115200 = **234** |
| 模式       | 轮询（无中断，无 FIFO）     |
| 接口       | 挂接 SoC 数据总线            |

**寄存器映射（基址 `0x10000000`）：**

| 地址偏移 | 名称      | 访问 | 说明                              |
|----------|-----------|------|-----------------------------------|
| `0x00`   | TXDATA    | W    | `[7:0]` 写入字节并立即发送       |
| `0x04`   | RXDATA    | R    | `[7:0]` 接收字节，`[31]` 数据有效|
| `0x08`   | STATUS    | R    | `[0]` TX 忙，`[1]` RX 有数据     |
| `0x0C`   | DIVISOR   | R/W  | 波特率分频值（默认 234）          |

---

## 7. CPU 流水线详细设计

### 7.1 五级流水线时序图

```
周期    1     2     3     4     5     6     7
指令1  IF    ID    EX    MEM   WB
指令2        IF    ID    EX    MEM   WB
指令3              IF    ID    EX    MEM   WB
```

### 7.2 各模块文件对应

| 模块          | 文件                   | 状态（v0.2） |
|---------------|------------------------|--------------|
| ALU           | `rtl/alu/alu.sv`       | 已生成       |
| 寄存器堆      | `rtl/core/regfile.sv`  | 已生成       |
| IF 阶段       | `rtl/core/if.sv`       | 已生成       |
| IF/ID 寄存器  | `rtl/core/if_id.sv`    | 已生成       |
| ID 阶段       | `rtl/core/id.sv`       | 已生成       |
| ID/EX 寄存器  | `rtl/core/id_ex.sv`    | 已生成       |
| EX 阶段       | `rtl/core/ex.sv`       | 已生成       |
| EX/MEM 寄存器 | `rtl/core/ex_mem.sv`   | 已生成       |
| MEM 阶段      | `rtl/core/mem.sv`      | 已生成       |
| MEM/WB 寄存器 | `rtl/core/mem_wb.sv`   | 已生成       |
| 冒险检测      | `rtl/core/hazard.sv`   | 已生成       |
| CPU 核顶层    | `rtl/core/cpu_core.sv` | 已生成       |

### 7.3 冒险处理

#### 数据冒险：前递（Forwarding）

```
EX 阶段（ex_mem 寄存器出口）
    {ex_reg_wen, ex_reg_waddr, ex_reg_wdata} ────────→ ID 阶段 fwd_ex_*

MEM 阶段（mem_wb 寄存器出口，含 Load 数据对齐）
    {mem_reg_wen, mem_reg_waddr, mem_reg_wdata} ─────→ ID 阶段 fwd_mem_*

优先级：EX > MEM > RegFile（在 ID 的 alu_src MUX 中选择）
```

#### Load-use 气泡（Hazard Unit）

```
条件：EX 阶段是 Load（ex_is_load=1）
      且 ex_reg_waddr ∈ {id_rs1, id_rs2}（且不为 x0）
操作：
  PC         → hold（不推进）
  IF/ID 寄存器 → hold（锁住）
  ID/EX 寄存器 → flush（插 NOP）
```

#### 控制冒险：跳转冲刷

```
条件：EX 阶段确认跳转（ex_jmp=1）
操作：
  IF/ID 寄存器 → flush（清空错误路径）
  ID/EX 寄存器 → flush（清空错误路径）
  PC           → jmp_addr（EX 阶段计算的目标地址）
代价：2 个周期气泡（taken branch penalty = 2 cycles）
```

---

## 8. 模块文件清单（完整）

```
MyRiscV/
├── rtl/
│   ├── alu/
│   │   ├── alu.svh               [宏定义] ALU_ADD ~ ALU_COPY_A
│   │   └── alu.sv                [模块]   纯组合逻辑 ALU
│   ├── core/
│   │   ├── core_define.svh       [宏定义] Opcode / funct3 / funct7 / INST_NOP
│   │   ├── if.sv                 [模块]   IF 阶段，PC 寄存器
│   │   ├── if_id.sv              [模块]   IF/ID 流水线寄存器
│   │   ├── id.sv                 [模块]   ID 阶段，完整 RV32I 译码 + 前递
│   │   ├── id_ex.sv              [模块]   ID/EX 流水线寄存器
│   │   ├── ex.sv                 [模块]   EX 阶段，ALU + 分支判断
│   │   ├── ex_mem.sv             [模块]   EX/MEM 流水线寄存器
│   │   ├── mem.sv                [模块]   MEM 阶段，总线请求 + Load 对齐
│   │   ├── mem_wb.sv             [模块]   MEM/WB 流水线寄存器
│   │   ├── regfile.sv            [模块]   32×32 寄存器堆，含调试端口
│   │   ├── hazard.sv             [模块]   冒险检测（load-use + branch flush）
│   │   └── cpu_core.sv           [模块]   CPU 核顶层，连接所有子模块
│   ├── debug/
│   │   ├── jtag_dtm.sv           [模块]   JTAG DTM（IEEE 1149.1 + DMI）
│   │   └── debug_module.sv       [模块]   Debug Module（Debug Spec v0.13.2）
│   ├── perips/
│   │   ├── iram.sv               [模块]   IRAM 16KB（BSRAM 推断，双端口：取指+调试）
│   │   ├── dram.sv               [模块]   DRAM 8KB（BSRAM 推断，字节使能）
│   │   ├── sim_ram.sv            [模块]   仿真用合一 RAM（含硬编码测试程序）
│   │   ├── uart.sv               [模块]   UART 8N1 115200
│   │   └── timer.sv              [模块]   CLINT Timer（Phase 4）
│   └── soc/
│       └── MyRiscV_soc_top.sv    [模块]   SoC 顶层
├── sim/
│   ├── tb/
│   │   ├── tb_alu.sv             [仿真]   ALU 单元测试
│   │   ├── tb_regfile.sv         [仿真]   RegFile 单元测试
│   │   └── tb_soc.sv             [仿真]   SoC 系统级测试（含 UART 解码）
│   └── scripts/
│       └── run_sim.sh            [脚本]   一键仿真
├── syn/
│   ├── constraints/
│   │   └── myriscv.pcf           [约束]   Tang Nano 9K 引脚约束
│   └── scripts/
│       └── synth.tcl             [脚本]   Yosys 综合脚本
├── sw/
│   ├── linker/link.ld            [链接]   内存布局
│   ├── startup/start.S           [汇编]   启动代码
│   └── test/                     [程序]   测试软件
├── tools/
│   └── jtag_loader.py            [工具]   Python JTAG 烧录脚本（Phase 2）
├── docs/
│   └── design_spec.md            [文档]   本文档
├── README.md
└── Makefile
```

---

## 9. FPGA 资源估算

| 资源              | 估算使用 | 可用量  | 使用率  |
|-------------------|----------|---------|---------|
| LUT4              | ~2,500   | 8,640   | ~29%    |
| FF（触发器）      | ~900     | 6,480   | ~14%    |
| BSRAM（18 Kbit）  | 14 块    | 26 块   | ~54%    |
| 片上 NOR Flash    | 76 KB    | 76 KB   | Phase 3 |

---

## 10. 开发阶段规划

### Phase 1：CPU Core + 仿真验证（当前阶段）

**目标：** 仿真通过，UART 输出 "Hello!\n"

**任务：**
- [x] 定义文件：`core_define.svh`、`alu.svh`
- [x] 生成所有流水线模块（12 个文件）
- [x] 生成 JTAG DTM（符合 Debug Spec）
- [x] 生成 Debug Module（符合 Debug Spec）
- [x] 生成 UART、SimRAM、SoC 顶层、Testbench
- [x] **代码审查**：检查接口匹配、信号位宽、include 路径
- [x] **修复已知 Bug**（旧代码遗留问题）
- [x] **iverilog 编译**：无语法/类型错误
- [x] **仿真运行**：`sim/out/tb_soc.vcd` 波形正确，UART 输出 "Hello!\n"

### Phase 2：FPGA 实现

**目标：** 综合通过，FPGA 板上跑通 UART 输出 + JTAG 调试

**任务：**
- [ ] 将 SimRAM 替换为 IRAM + DRAM（独立模块，BSRAM 推断）
- [ ] Yosys 综合：`synth_gowin -bsram`，无错误警告
- [ ] nextpnr 布局布线：满足 27 MHz 时序
- [ ] openFPGALoader 烧录验证
- [ ] OpenOCD 连接 JTAG，验证 halt/resume/寄存器读写/内存读写

### Phase 3：Flash 控制器

**目标：** CPU 可从片上 NOR Flash（`0x20000000`）读取数据

**任务：**
- [ ] 实现 `flash_ctrl.sv`（通过 Gowin Flash 原语 `Flash_DP`）
- [ ] 接入 SoC 数据总线

### Phase 4：CLINT Timer + 软件中断

**任务：**
- [ ] 实现 `timer.sv`（mtime + mtimecmp，地址 `0x02000000`）
- [ ] 接入 CPU 中断输入（需扩展 CSR 支持 mstatus/mie/mip/mepc/mcause）

### Phase 5（可选扩展）

- [ ] M 扩展（MUL/DIV），利用 GW1NR-9C 内置 DSP
- [ ] 单步执行、硬件断点（trigger module，Debug Spec §5）
- [ ] 外部 SPI Flash 控制器（板载 4MB P25Q32U）
- [ ] GDB TUI 调试体验优化

---

## 11. 立即下一步（Phase 1 剩余工作）

按以下顺序完成 Phase 1：

```
Step 1：代码审查
  - 检查所有生成文件的 include 路径
  - 检查模块端口名称匹配（cpu_core ↔ jtag_dtm ↔ debug_module ↔ soc_top）
  - 检查 sim_ram 机器码是否正确

Step 2：iverilog 编译
  make sim_soc
  → 修复所有编译错误

Step 3：仿真运行
  vvp sim/out/tb_soc
  → 观察波形，确认 UART 输出 "Hello!\n"

Step 4：机器码验证
  → 使用 RISC-V 反汇编工具验证 sim_ram.sv 中的机器码正确
```

---

## 12. 已知 Bug 记录

| 文件               | 位置     | 问题描述                                   | 状态  |
|--------------------|----------|--------------------------------------------|-------|
| `alu.sv`（旧）     | L2       | `include` 拼写错误（已在新版本修正）        | 已修复 |
| `alu.sv`（旧）     | L32,35   | SRL/SRA 互换（新版本已正确实现）            | 已修复 |
| `core_define.svh`（旧）| -    | 缺少 InstAddrWidth/InstWidth（新版本已补充）| 已修复 |
| `id.sv`（旧）      | L111     | 符号扩展位索引错误（新版本重写）             | 已修复 |
| `wb.sv`            | -        | 旧空文件存在，与新版本的 WB 内联设计冲突    | 待确认 |
| `jtag_dm.sv`       | -        | 旧空文件存在，已由新的 jtag_dtm.sv 替代     | 待清理 |
| `ram.sv`, `rom.sv` | -        | 旧空文件存在，已由 sim_ram.sv 替代          | 待清理 |

---

## 13. 仿真与调试指南

### 13.1 仿真命令

```bash
# 编译 SoC 仿真（OSS CAD Suite iverilog 使用 -I，不支持 +incdir+）
iverilog -g2012 \
    -Irtl/alu -Irtl/core \
    rtl/alu/alu.sv \
    rtl/core/regfile.sv rtl/core/if.sv rtl/core/if_id.sv \
    rtl/core/id.sv rtl/core/id_ex.sv rtl/core/ex.sv \
    rtl/core/ex_mem.sv rtl/core/mem.sv rtl/core/mem_wb.sv \
    rtl/core/hazard.sv rtl/core/cpu_core.sv \
    rtl/debug/jtag_dtm.sv rtl/debug/debug_module.sv \
    rtl/perips/uart.sv rtl/perips/sim_ram.sv \
    rtl/soc/MyRiscV_soc_top.sv \
    sim/tb/tb_soc.sv \
    -o sim/out/tb_soc

# 运行仿真
vvp sim/out/tb_soc

# 查看波形
gtkwave sim/out/tb_soc.vcd
```

### 13.2 OpenOCD 连接配置（Phase 2）

```tcl
# openocd.cfg
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

```bash
# 连接
openocd -f openocd.cfg

# GDB 调试
riscv32-unknown-elf-gdb firmware.elf
(gdb) target remote :3333
(gdb) info registers
(gdb) x/10i $pc
```

---

## 14. 参考规范

| 文档 | 链接 | 说明 |
|------|------|------|
| RISC-V ISA Spec v20191213 | https://riscv.org/technical/specifications/ | 指令集 |
| RISC-V Debug Spec v0.13.2 | https://github.com/riscv/riscv-debug-spec/releases | JTAG 调试规范 |
| GW1NR Series DS117 | https://cdn.gowinsemi.com.cn/DS117E.pdf | BSRAM 配置 |
| Gowin BSRAM UG285 | https://www.gowinsemi.com | BSRAM 详解 |
| Gowin User Flash UG295 | https://www.gowinsemi.com | 片上 Flash |
| Tang Nano 9K 原理图 | https://dl.sipeed.com/shareURL/TANG/Nano9K/2_Schematic | 引脚分配 |
| OSS CAD Suite | https://github.com/YosysHQ/oss-cad-suite-build | 工具链 |
| OpenOCD RISC-V | https://github.com/riscv/riscv-openocd | 调试工具 |
