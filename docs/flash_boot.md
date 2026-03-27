# MyRiscV Flash 启动修改方案

## 目标
像普通单片机（如 STM32）一样：**烧录 bitstream 和程序到 FPGA Flash，上电自动从 Flash 启动执行**。

---

## 架构修改概览

### 当前架构（Phase 2）
```
复位 → PC=0x80000000 (IRAM) → 执行
                ▲
                │
           JTAG 加载程序
```

### 目标架构（Flash 启动）
```
复位 → PC=0x20000000 (Flash) → 取指执行
         │
         └─→ Flash 控制器（2 周期延迟）→ 插入等待周期
```

---

## 需要修改的文件

### 1. `rtl/core/core_define.svh`
修改复位地址：
```systemverilog
// 修改前：
`define CpuResetAddr    32'h80000000

// 修改后：
`define CpuResetAddr    32'h20000000   // Flash 起始地址
```

---

### 2. `rtl/core/cpu_core.sv`
添加 Flash 等待逻辑（XIP 支持）：

```systemverilog
// 修改 IF 阶段：
// IRAM/Flash 同步读等待
reg iram_wait;
always @(posedge clk) begin
    if (rst)
        iram_wait <= 1'b1;
    else if (iram_wait)
        iram_wait <= 1'b0;
    else if (ex_jmp && !load_use_stall && !dbg_halted)
        iram_wait <= 1'b1;
    // Flash 访问：额外等待 1 周期（Flash 需要 2 周期）
    else if (flash_access && !flash_wait_done)
        iram_wait <= 1'b1;
end

// Flash 访问检测
wire flash_access = (iram_addr[31:29] == 3'b0010);  // 0x2xxxxxxx
reg  flash_wait_done;
always @(posedge clk) begin
    if (rst)
        flash_wait_done <= 1'b0;
    else if (flash_access)
        flash_wait_done <= 1'b1;
    else
        flash_wait_done <= 1'b0;
end

// IF 暂停条件
wire if_hold_pre = load_use_stall | dbg_halted | iram_wait;
```

---

### 3. `rtl/soc/MyRiscV_soc_top.sv`
修改 IRAM 和 Flash 的连接，支持 Flash 取指：

```systemverilog
// 添加 Flash 指令读接口
wire [31:0] flash_irdata;
wire        flash_irdata_vld;

// Flash 控制器增加指令读端口
FlashCtrl u_flash_ctrl (
    .clk           (clk),
    .rst           (rst),
    // 指令端口（CPU 取指）
    .iaddr         (iram_addr),
    .iren          (sel_flash_if),     // Flash 取指使能
    .irdata        (flash_irdata),
    .irdata_vld    (flash_irdata_vld),
    // 数据端口（CPU 读写）
    .cpu_addr      (dbus_addr),
    .cpu_ren       (dbus_ren & sel_flash),
    .cpu_rdata     (flash_rdata),
    .cpu_rdata_vld (flash_rdata_vld)
);

// IRAM 数据 MUX（IRAM 或 Flash）
assign iram_rdata = sel_flash_if ? flash_irdata : iram_drdata;

// Flash 取指译码
wire sel_flash_if = (iram_addr[31:17] == 15'h1000);
```

---

### 4. `rtl/perips/flash_ctrl.sv`
增加指令读端口：

```systemverilog
module FlashCtrl (
    // ... 现有端口 ...

    // 新增：指令读端口（供 CPU 取指）
    input  wire [31:0] iaddr,
    input  wire        iren,
    output reg  [31:0] irdata,
    output reg         irdata_vld
);

// 指令读状态机（与数据读共享 Flash 宏）
always @(posedge clk) begin
    if (rst) begin
        irdata_vld <= 1'b0;
    end else if (iren) begin
        // Flash 读延迟 2 周期
        irdata     <= flash_mem[iaddr[16:2]];  // 仿真
        irdata_vld <= 1'b1;  // 次周期有效
    end else begin
        irdata_vld <= 1'b0;
    end
end
```

---

### 5. `rtl/perips/iram.sv`
简化为纯数据 RAM（不再存储启动代码）：

```systemverilog
// 移除 initial $readmemh
// 仅保留数据端口，指令端口保留但上电内容为 X
```

---

### 6. `rtl/perips/flash_init.mem`
存放程序文件（由 helloworld.bin 生成）：

```
// Flash 内容格式（32 位字，小端）
// 地址 0x20000000: 第一条指令
80006137  // lui sp, 0x80006
008000ef  // jal ra, main
...
```

---

## 工具链修改

### 修改链接脚本 `sw/helloworld/link.ld`
```ld
MEMORY {
    FLASH (rx) : ORIGIN = 0x20000000, LENGTH = 76K
    DRAM  (rwx): ORIGIN = 0x80004000, LENGTH = 8K
}

SECTIONS {
    .text : {
        *(.text)
        *(.text.*)
        . = ALIGN(4);
    } > FLASH

    .rodata : {
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4);
    } > FLASH

    .data : {
        _data_start = .;
        *(.data)
        *(.data.*)
        . = ALIGN(4);
        _data_end = .;
    } > DRAM AT > FLASH

    .bss : {
        _bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DRAM

    _stack_top = ORIGIN(DRAM) + LENGTH(DRAM);
}
```

### 修改构建脚本 `sw/helloworld/build_all.sh`
```bash
# 添加 Flash 烧录目标
flash:
    openocd -f openocd.cfg \
        -c "program helloworld.bin 0x20000000 verify reset exit"
```

---

## 使用流程

### 1. 编译程序
```bash
cd sw/helloworld
./build_all.sh build
```

### 2. 生成 Flash 初始化文件
```bash
python3 bin2flash.py helloworld.bin ../../rtl/perips/flash_init.mem
```

### 3. 综合 + 布局布线
```bash
make synth pnr bitstream
```

### 4. 烧录到 FPGA
```bash
make prog
```

### 5. 上电后自动运行
- FPGA 配置加载后，CPU 自动从 `0x20000000` 取指
- 执行 helloworld 程序
- UART TX 输出 `Hello, World!`

---

## 时间分析

### Flash 读时序
```
周期 T0: CPU 输出地址 iren=1
周期 T1: Flash 宏访问（建立时间）
周期 T2: 数据输出 irdata_vld=1
周期 T3: CPU 采样数据（插入 1 周期等待）
```

### 性能影响
- Flash 访问：2 周期延迟
- IRAM 访问：1 周期延迟
- 程序在 Flash 中顺序执行时，每 2 条指令损失 1 周期
- 估算性能：约 67% 峰值（与缓存命中率相关）

---

## 可选优化

### 1. 添加指令缓存（I-Cache）
- 4KB 直接映射 I-Cache
- 命中率 > 90% 时性能接近 IRAM

### 2. 关键代码复制到 IRAM
- Bootloader 将热代码从 Flash 复制到 IRAM
- 中断向量、关键函数在 IRAM 执行

### 3. Flash XIP + IRAM Scratchpad
- Flash 用于取指
- IRAM 用于数据/栈
- 零成本切换

---

## 验证步骤

### 1. 仿真验证
```bash
# 修改 iram_init.mem 为空
# 修改 flash_init.mem 为 helloworld
make sim_soc
```

### 2. FPGA 验证
- 烧录 bitstream
- 用示波器/逻辑分析仪测量 Flash 读时序
- 确认 UART 输出

---

## 风险与注意事项

1. **Flash 时序**：确保 FPGA Flash 宏的建立/保持时间满足 27 MHz
2. **综合约束**：Flash 路径需要时序约束
3. **调试**：首次启动失败时用 JTAG 强制 PC 验证 Flash 内容
4. **大小端**：bin 转 flash 时注意字节序

---

## 完成清单

- [ ] 修改 `core_define.svh` 复位地址
- [ ] 修改 `cpu_core.sv` Flash 等待逻辑
- [ ] 修改 `FlashCtrl` 增加指令读端口
- [ ] 修改 `MyRiscV_soc_top` 连接
- [ ] 修改链接脚本到 Flash
- [ ] 创建 bin2flash.py 工具
- [ ] 仿真验证
- [ ] FPGA 验证
