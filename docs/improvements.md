# MyRiscV 未来改进计划与潜在优化

> 文档版本：v1.0
> 更新日期：2026-03-19
> 当前阶段：Phase 2（仿真完成，综合进行中）

---

## 改进路线图总览

| 编号 | 改进项 | 所属阶段 | 优先级 | 难度 | 状态 |
|------|--------|----------|--------|------|------|
| S1 | 修复 SDPB INIT_RAM 参数 `include` | Phase 2 | 紧急 | 简单 | 待修复 |
| S2 | 验证综合后 BSRAM 初始化正确 | Phase 2 | 紧急 | 简单 | 待验证 |
| M1 | CSR 最小集支持（中断机制） | Phase 3 | 高 | 中等 | 未实现 |
| M2 | CLINT Timer + 软中断 | Phase 3 | 高 | 中等 | 占位空文件 |
| M3 | JTAG 调试完善（abstract cmd/单步/progbuf） | Phase 3 | 高 | 困难 | 部分实现 |
| M4 | Flash 写/擦除（完善 FlashCtrl） | Phase 3 | 中 | 中等 | 只读已实现 |
| M5 | MCU 烧录流程（JTAG 写 Flash） | Phase 3 | 中 | 中等 | 未实现 |
| P1 | PLL 提频：27MHz → 50MHz | Phase 3 | 中 | 简单 | 未使用 |
| P2 | 消除不必要的 iram_wait stall | Phase 3 | 中 | 中等 | 已知问题 |
| M6 | Flash SBA 支持 | Phase 3 | 低 | 中等 | 未实现 |
| L1 | M 扩展（乘除法，使用 DSP） | Phase 4 | 中 | 中等 | 未实现 |
| L2 | 分支预测（静态不跳转预测） | Phase 4 | 低 | 中等 | 未实现 |
| L3 | 外部 SPI Flash 控制器（4MB P25Q32U） | Phase 4 | 低 | 困难 | 未实现 |
| L4 | GPIO 外设 | Phase 4 | 低 | 简单 | 未实现 |
| L5 | SPI/I2C 外设 | Phase 4 | 低 | 中等 | 未实现 |
| L6 | HDMI 输出 | Phase 4+ | 低 | 困难 | 未实现 |
| T1 | sw/ C 工具链完善（printf 支持） | Phase 3 | 中 | 中等 | 基础可用 |
| T2 | JTAG 烧录脚本（tools/jtag_loader.py） | Phase 3 | 中 | 中等 | 占位文件 |
| T3 | GDB 调试脚本和文档 | Phase 3 | 低 | 简单 | 未实现 |

---

## 短期改进（Phase 2 综合阶段）

### S1 — 修复 SDPB INIT_RAM 参数 `include` 机制

**问题描述**

这是当前最紧迫的问题，直接影响综合后上板能否正常工作。

`iram.sv` 在综合路径下例化 SDPB 原语时，`INIT_RAM_00` 到 `INIT_RAM_3F` 参数全部硬编码为 `256'h0`，而非从 `mem2init.py` 脚本生成的 `iram_init_params.vh` 中读取。这意味着综合后的 IRAM 内容为全零，CPU 上电后取指全为 `NOP`（或非法指令），程序无法执行。

`mem2init.py` 已能正确将 `iram_init.mem` 转换成 SDPB 所需的 256bit × 64 参数格式，但 `iram.sv` 的综合分支并未使用该文件。

**建议方案**

1. 在 `iram.sv` 综合分支的 SDPB 例化块顶部添加 `` `include "iram_init_params.vh" ``：

```systemverilog
`ifndef SIMULATION
  // 综合路径：直接例化 SDPB
  `include "iram_init_params.vh"   // 生成：INIT_RAM_00 ~ INIT_RAM_3F
  SDPB #(
      .INIT_RAM_00(INIT_RAM_00),
      .INIT_RAM_01(INIT_RAM_01),
      // ... 其余参数
  ) u_sdpb_0 ( ... );
`endif
```

2. `iram_init_params.vh` 由 Makefile 在综合前自动调用 `mem2init.py` 生成，确保每次修改程序后自动更新。

3. Makefile 中 `synth` target 前置依赖 `iram_init_params.vh`：

```makefile
$(SYN_DIR)/iram_init_params.vh: $(PERIPS_DIR)/iram_init.mem
	python3 tools/mem2init.py $< > $@

synth: $(SYN_DIR)/iram_init_params.vh $(RTL_SRCS)
	yosys -p "..."
```

4. 综合完成后，通过读回 BSRAM 初始数据（例如 OpenOCD `mdw 0x80000000 16`）验证前几条指令正确匹配 `iram_init.mem`。

**实现难度**：简单
**所属阶段**：Phase 2（当前最高优先级）

---

### S2 — 验证综合后 BSRAM 初始化正确

**问题描述**

即使 S1 修复后，仍需通过上板测试确认 BSRAM 初始内容加载正确，且 CPU 能正确取指并执行 UART 输出"Hello!\n"。

**建议方案**

1. 烧录后通过 UART 观察输出，确认"Hello!\n"出现。
2. 若无 UART 输出，用 OpenOCD + GDB 连接 JTAG，执行 `x/16xw 0x80000000` 检查 IRAM 内容。
3. 若 BSRAM 内容全零，说明 S1 未正确生效，重新检查 `include` 路径和 Makefile 依赖。

**实现难度**：简单
**所属阶段**：Phase 2

---

## 中期改进（Phase 3~4）

### M1 — CSR 最小集支持（中断机制）

**问题描述**

当前 CPU 无任何 CSR 寄存器，无法处理中断和异常。缺少 CSR 意味着：无法使用 CLINT Timer 中断、无法使用 ECALL/EBREAK 系统调用、无法正确处理非法指令异常。这是从裸机轮询程序过渡到 RTOS 的必要前提。

**建议方案**

实现 RV32I 中断所需的最小 CSR 集：

| CSR 地址 | 寄存器 | 功能 |
|---------|--------|------|
| 0x300 | mstatus | 全局中断使能（MIE 位） |
| 0x304 | mie | 中断使能（MTIE/MSIE/MEIE） |
| 0x344 | mip | 中断挂起状态（只读） |
| 0x305 | mtvec | 中断向量基地址 |
| 0x341 | mepc | 异常返回地址 |
| 0x342 | mcause | 异常原因 |
| 0xF11 | mvendorid | 厂商 ID（可硬编码 0） |
| 0xF14 | mhartid | hart ID（硬编码 0） |

在 ID 阶段解码 CSR 指令（CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI），WB 阶段写回。中断控制器接收外部中断请求，在 IF 阶段插入跳转到 `mtvec`。

**实现难度**：中等
**所属阶段**：Phase 3

---

### M2 — CLINT Timer + 软中断

**问题描述**

`timer.sv` 当前为占位空文件，`wb.sv`（Wishbone 总线？）同样为空。无 Timer 意味着无法实现周期性任务调度，无法支持 FreeRTOS 等 RTOS 的 tick 中断。

**建议方案**

实现标准 RISC-V CLINT（Core Local Interruptor）：

1. 在地址 `0x02000000` 实现 `mtime`（64bit，每时钟周期递增）和 `mtimecmp`（64bit，可写）寄存器。
2. 当 `mtime >= mtimecmp` 时，拉高 MTIP（machine timer interrupt pending）。
3. MTIP 信号连接到 CPU 核的中断输入，触发 M-mode 定时器中断。
4. M2 依赖 M1（CSR 支持）才能正常工作。

地址映射（标准 CLINT）：

```
0x02000000: msip（软中断，32bit）
0x02004000: mtimecmp[0] 低32位
0x02004004: mtimecmp[0] 高32位
0x0200BFF8: mtime 低32位
0x0200BFFC: mtime 高32位
```

**实现难度**：中等
**所属阶段**：Phase 3

---

### M3 — JTAG 调试完善（Abstract Command / 单步 / Progbuf）

**问题描述**

当前 Debug Module 的 `abstract command` 实现不完整：
- Progbuf 执行（Program Buffer 机制）未实现
- 单步执行（step bit in dcsr）未实现
- 硬件断点（trigger CSR）未实现

这使得 GDB 只能读写寄存器和内存，无法设置断点、单步调试。

**建议方案**

按 RISC-V Debug Spec v0.13.2 分阶段实现：

1. **Abstract Command 完整化**：实现 `command` 寄存器的 Access Register 命令（cmdtype=0），支持通过 Data0/Data1 读写所有 32 个通用寄存器和 PC。

2. **Progbuf 执行**：在 DM 内部维护 2 条指令的 Program Buffer（progbufsize=2），CPU halt 后可跳转执行 progbuf，支持 GDB 的内存访问操作。

3. **单步执行**：在 `dcsr.step=1` 时，CPU 执行一条指令后自动重新进入 halt 状态。需要在 EX 阶段添加单步计数器。

4. **硬件断点**：实现至少 2 个 PC 比较触发器（trigger），当 IF 取指地址命中断点地址时触发 halt。

**实现难度**：困难
**所属阶段**：Phase 3

---

### M4 — Flash 写/擦除（完善 FlashCtrl）

**问题描述**

当前 `FlashCtrl` 只实现了 `S_IDLE → S_READ` 状态，只能读取用户 Flash 区域（76KB）。没有写入和擦除能力，意味着：
- 无法通过 JTAG 烧录程序到 Flash
- 无法实现 Flash 上的持久化存储

**建议方案**

扩展 FlashCtrl 状态机，增加以下操作：

| 操作 | 命令字 | 说明 |
|------|--------|------|
| 页擦除 | 0x20 | 擦除 256B 一页 |
| 扇区擦除 | 0xD8 | 擦除 4KB 一扇区 |
| 页编程 | 0x02 | 写入最多 256B |
| 读状态寄存器 | 0x05 | 等待写操作完成（WIP 位） |

状态机新增状态：`S_ERASE_CMD → S_ERASE_WAIT`、`S_WRITE_CMD → S_WRITE_DATA → S_WRITE_WAIT`。

注意：GW1NR 片上 Flash 使用 Gowin 专用 Flash 控制原语（FLASH256K），API 与标准 SPI Flash 不同，需参考 Gowin 用户手册 UG295。

**实现难度**：中等
**所属阶段**：Phase 3

---

### M5 — MCU 烧录流程（JTAG 写 Flash）

**问题描述**

当前程序通过 SDPB INIT_RAM 参数在综合时固化到 BSRAM，修改程序需要重新综合（~10 分钟）。理想流程是：综合一次生成固定 bitstream，后续通过 JTAG 将新程序写入 Flash，上电后 CPU 从 Flash 引导。

**建议方案**

1. 完成 M4（Flash 写/擦除）。
2. 完成 M3（JTAG Progbuf），使 GDB 能通过 progbuf 执行 Flash 写入指令。
3. 编写 `tools/jtag_loader.py`：接收 ELF 或 `.mem` 文件，通过 OpenOCD 的 `load_image` 命令将程序写入 Flash 用户区。
4. 修改 SoC 复位逻辑：上电后 PC 从 Flash 映射区起始地址（`0x20000000`）开始取指，而不是 IRAM。

备选方案：保留 IRAM 引导方式，在 IRAM 中放置小型 bootloader，由 bootloader 通过 UART 接收程序并写入 DRAM 或 Flash 执行。

**实现难度**：中等
**所属阶段**：Phase 3

---

### M6 — Flash 区域 SBA 支持

**问题描述**

当前 Debug Module 的 System Bus Access (SBA) 只支持 IRAM（`0x80000000~0x80003FFF`）和 DRAM（`0x80004000~0x80005FFF`）区域。对 Flash 区域（`0x20000000~0x20012FFF`）的 SBA 访问会超时或返回错误数据，导致 GDB 无法通过 SBA 读取 Flash 内容。

**建议方案**

在 `debug_module.sv` 的 SBA 地址解码中增加 Flash 区域：

```systemverilog
// SBA 地址解码
always_comb begin
    if (sba_addr inside {[32'h80000000:32'h80003FFF]}) sba_target = SBA_IRAM;
    else if (sba_addr inside {[32'h80004000:32'h80005FFF]}) sba_target = SBA_DRAM;
    else if (sba_addr inside {[32'h20000000:32'h20012FFF]}) sba_target = SBA_FLASH; // 新增
    else sba_target = SBA_NONE;
end
```

Flash SBA 需要等待 FlashCtrl 的读操作完成（多拍延迟），需在 SBA 状态机中增加等待状态。依赖 M4 完成。

**实现难度**：中等
**所属阶段**：Phase 3

---

## 性能优化

### P1 — PLL 提频：27MHz → 50MHz

**问题描述**

当前时钟直接使用 Tang Nano 9K 板载 27MHz 晶振，未使用 GW1NR 片上 rPLL。27MHz 时钟下 CPU 理论 IPC≈0.6（含各种 stall），实际吞吐量约 16MIPS。使用 PLL 提频到 50MHz 可将吞吐量提高 85%，且 GW1NR-9C 的 rPLL 支持最高 400MHz 输出（受 LUT 时序约束限制，实际 RISC-V 核约 50~80MHz 可达）。

**建议方案**

1. 在 `rtl/soc/MyRiscV_soc_top.sv` 顶层添加 Gowin rPLL 例化：

```systemverilog
rPLL #(
    .FCLKIN("27"),       // 输入 27MHz
    .IDIV_SEL(0),        // 分频比 = IDIV_SEL + 1 = 1
    .FBDIV_SEL(1),       // 倍频比 = FBDIV_SEL + 2 = 3（配合 ODIV_SEL）
    .ODIV_SEL(2),        // 输出分频 = 4
    // 27 × 3 / 4 ≈ 20MHz，调整参数到 50MHz：
    // 27 × (FBDIV_SEL+2) / ODIV_SEL = 50
    .DYN_SDIV_SEL(2),
    .CLKOUT_FT_DIR(1'b1),
    .CLKOUTP_FT_DIR(1'b1)
) u_pll (
    .CLKIN(clk_27m),
    .CLKOUT(clk_core),   // 50MHz 主时钟
    .LOCK(pll_lock)
);
```

2. 使用 `pll_lock` 信号控制系统复位，PLL 锁定前保持全局复位。
3. UART 分频系数需相应修改：50MHz / 115200 ≈ 434。
4. 运行 nextpnr 时序分析，确认所有路径满足 50MHz 约束。

**实现难度**：简单（Gowin rPLL 有模板可参考）
**所属阶段**：Phase 3

---

### P2 — 消除不必要的 iram_wait stall

**问题描述**

当前 `iram_wait` 机制在每次 branch/jump 指令后强制插入 1 拍等待，原因是 SDPB 读取需要 2 拍（流水线 IF 到 BSRAM 输出有 1 拍额外延迟）。在 UART 忙等循环中，大量 `beq`/`bne` 导致 CPU 效率低下。

仿真数据：发送"Hello!\n"（7 字节）耗时约 590μs，理论值（纯 UART 时间）约 608μs（7 × 10bit / 115200）。两者接近，说明 CPU 执行时间对总耗时影响较小，但长期来看 stall 积累会影响复杂程序性能。

**建议方案**

1. **方案 A（推荐）**：在 IF 阶段增加 PC 寄存器预测逻辑，BSRAM 以固定地址提前 1 拍请求，消除顺序取指的额外等待。只有在实际发生跳转时才需要 1 拍重填。

2. **方案 B**：将 SDPB 改为注册输出（`READ_MODE=0`，输出寄存器模式），在 IF 阶段 stall 传播时同步处理，使流水线行为与仿真模型一致。

3. 仅针对顺序取指优化，对非顺序跳转仍保留 1 拍等待（不可避免）。

**实现难度**：中等
**所属阶段**：Phase 3

---

### L1 — M 扩展（乘除法，使用 DSP）

**问题描述**

RV32I 基础指令集不含乘除法，实现 M 扩展（RV32IM）需要额外硬件。软件模拟乘法（移位+加法循环）约需 32 周期，对数值计算程序性能影响很大。GW1NR-9C 内置 2 个 18×18 DSP 乘法器，当前未使用。

**建议方案**

1. 在 `alu.sv` 中添加 MUL/MULH/MULHU/MULHSU 指令支持，使用 GW1NR DSP18 原语实现 32×32 乘法（需要 2 个 DSP 级联）。
2. DIV/DIVU/REM/REMU 用 LUT 实现迭代除法器（34 周期，多拍操作，需在流水线中插入 stall）。
3. 或使用仅 LUT 实现的 32×32 组合乘法器（约 200 LUT，延迟约 5ns，可满足 50MHz 时序）。

**实现难度**：中等
**所属阶段**：Phase 4

---

### L2 — 分支预测（静态不跳转预测）

**问题描述**

当前流水线在 EX 阶段判断分支结果，每次预测错误（即实际发生跳转）需要冲刷 IF+ID 两级流水线，造成 2 个周期惩罚。在循环密集型代码中（如 UART 发送循环、内存拷贝），分支预测错误率接近 50%，严重影响 IPC。

**建议方案**

实现静态"总预测不跳转"策略：

1. IF 阶段始终预测 PC+4（当前实现已是如此）。
2. 在 EX 阶段检测到实际跳转时，冲刷 IF/ID 流水线（已实现）。
3. 改进：将分支目标地址提前到 ID 阶段计算（offset 加法），减少 1 个周期惩罚，使分支代价降至 1 cycle。

更高级的方案（Phase 4+）：2-bit 饱和计数器动态分支预测表（BTB），对内层循环预测准确率 >95%。

**实现难度**：中等
**所属阶段**：Phase 4

---

## 功能扩展

### L3 — 外部 SPI Flash 控制器（4MB P25Q32U）

**问题描述**

Tang Nano 9K 板载 4MB P25Q32U SPI Flash（接在 FPGA 的 SPI 引脚上）。当前仅使用片内 76KB 用户 Flash，4MB 外部 Flash 可以存储大型程序（如带操作系统的固件），通过 XIP（Execute In Place）或 DMA 加载到 IRAM 执行。

**建议方案**

1. 实现标准 SPI Master 控制器，支持 Fast Read (0x0B) 命令，带 XIP 缓存（简单直接映射缓存，16 个 cacheline × 32B）。
2. 地址映射：`0x30000000~0x303FFFFF`（4MB）。
3. 上电后 bootloader 从 SPI Flash 偏移 `0x100000` 处加载程序到 IRAM，然后跳转执行。

**实现难度**：困难（需要精确的 SPI 时序控制和缓存设计）
**所属阶段**：Phase 4

---

### L4 — GPIO 外设

**问题描述**

无 GPIO 外设，无法控制板载 LED（Tang Nano 9K 有 6 个 LED），无法与外部设备交互。

**建议方案**

实现简单的 GPIO 控制器：

```
地址 0x40000000: GPIO_DIR（输出方向寄存器，32bit）
地址 0x40000004: GPIO_OUT（输出数据寄存器，32bit）
地址 0x40000008: GPIO_IN （输入数据寄存器，32bit，只读）
```

优先映射 6 个 LED（低 6 位），可选扩展至 16 个通用 IO。
硬件资源消耗极小（<20 LUT）。

**实现难度**：简单
**所属阶段**：Phase 4

---

### L5 — SPI / I2C 外设

**问题描述**

无 SPI/I2C 控制器，无法连接传感器、显示屏等外设。

**建议方案**

1. **SPI Master**：4 线 SPI（MOSI/MISO/SCLK/CS），支持 Mode 0/3，可配置分频，地址 `0x40001000`。
2. **I2C Master**：标准 I2C，支持 7bit 地址，400KHz，地址 `0x40002000`。

两者均可从开源 RISC-V SoC 项目（如 PicoRV32 外设库）移植修改。

**实现难度**：中等
**所属阶段**：Phase 4

---

### L6 — HDMI 输出

**问题描述**

Tang Nano 9K 板载 HDMI 接口（通过 FPGA IO 引脚直接驱动 TMDS 信号），可以输出视频画面。实现 HDMI 需要 TMDS 编码器和视频时序生成器，资源消耗较大（约 1000 LUT），但可以实现终端字符显示或简单图形输出。

**建议方案**

1. 实现 640×480@60Hz VGA 时序生成器 + TMDS 编码器（使用 Gowin ELVDS_OBUF 原语）。
2. 维护 80×30 字符 framebuffer（存在 BSRAM 中，约 2400 字节，需 2 块 BSRAM）。
3. CPU 通过内存映射寄存器写字符到 framebuffer，实现终端输出。
4. 此功能消耗约 1000 LUT（当前剩余约 6000 LUT），资源充裕。

**实现难度**：困难（TMDS 时序和 Gowin 原语使用复杂）
**所属阶段**：Phase 4+

---

## 工具链改进

### T1 — sw/ C 工具链完善（printf 支持）

**问题描述**

当前软件栈只支持基础汇编和简单 C 程序（无标准库）。缺少 `printf` 等格式化输出函数，调试输出只能手动拼装字符串，开发效率低。

**建议方案**

1. 基于 `newlib-nano` 实现轻量级 `printf`（仅需约 2KB Flash）：
   - 实现 `_write` 系统调用，将输出重定向到 UART。
   - 实现 `_sbrk` 支持动态内存分配（基于 DRAM 8KB）。
2. 提供 `sw/lib/syscalls.c` 包含上述系统调用实现。
3. Makefile 中添加 `--specs=nano.specs -lc -lnosys` 链接选项。

**实现难度**：中等
**所属阶段**：Phase 3

---

### T2 — JTAG 烧录脚本（tools/jtag_loader.py）

**问题描述**

`tools/jtag_loader.py` 当前为占位空文件。没有自动化烧录脚本，每次更新程序需要手动操作 OpenOCD 命令，流程繁琐。

**建议方案**

基于 OpenOCD TCL 接口（telnet 或 Python `openocd` 库）实现：

```python
# tools/jtag_loader.py 基本流程
# 1. 连接 OpenOCD（telnet localhost 4444）
# 2. halt CPU
# 3. 将 ELF 或 .mem 文件写入 IRAM（load_image）
# 4. 设置 PC 到程序入口
# 5. resume CPU
# 可选：-flash 模式写入 Flash（依赖 M4/M5 完成）
```

同时提供 OpenOCD 配置文件 `tools/openocd.cfg`（已有 JTAG DTM，确认 OpenOCD 能正确识别 IDCODE）。

**实现难度**：中等
**所属阶段**：Phase 3

---

### T3 — GDB 调试脚本和文档

**问题描述**

缺少 GDB 连接和调试的文档与脚本，首次使用 JTAG 调试时需要大量手动配置。

**建议方案**

1. 提供 `tools/gdbinit` 模板：

```
target extended-remote :3333
set arch riscv:rv32
file build/program.elf
monitor reset halt
load
```

2. 提供 `docs/debug_guide.md`，说明 OpenOCD + GDB 连接步骤、常用调试命令（`break`、`step`、`info registers`、`x/16xw 0x80000000`）。

3. 在 Makefile 中添加 `make debug` target，自动启动 OpenOCD 并连接 GDB。

**实现难度**：简单
**所属阶段**：Phase 3

---

## 附录：硬件资源利用率估算

| 资源 | 总量 | 当前使用 | Phase 3 预估 | Phase 4 预估 |
|------|------|----------|--------------|--------------|
| LUT4 | 8,640 | ~2,510 (29%) | ~3,500 (41%) | ~5,000 (58%) |
| FF | 6,480 | ~910 (14%) | ~1,200 (19%) | ~1,600 (25%) |
| BSRAM 18K | 26 块 | 14 块 (54%) | 16 块 (62%) | 20 块 (77%) |
| DSP | 2 个 | 0 (0%) | 0 (0%) | 2 (100%) |
| PLL | 1 个 | 0 (0%) | 1 (100%) | 1 (100%) |

注：LUT/FF 估算基于 Phase 2 综合报告，Phase 3/4 数据为估算值，实际以综合结果为准。BSRAM 增量来自 HDMI framebuffer（2 块）和 SBA 缓存等。
