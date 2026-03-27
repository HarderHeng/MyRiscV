# MyRiscV Hello World 可执行性分析报告

## 1. BIN 文件分析

### 二进制内容
```
地址     内容 (32-bit little-endian)         指令
------------------------------------------------------------
0x00     0x80006137                         lui     sp,0x80006
0x04     0x008000ef                         jal     ra,0x0c
0x08     0x0000006f                         j       0x08 (死循环)
0x0C     0xff010113                         addi    sp,sp,-16
0x10     0x00112623                         sw      ra,12(sp)
0x14     0x00000297                         auipc   t0,0x0
0x18     0x04028293                         addi    t0,t0,64
0x1C     0x0002c303                         lbu     t1,0(t0)
0x20     0x02030463                         beqz    t1,0x48
0x24     0x100003b7                         lui     t2,0x10000
0x28     0x00838393                         addi    t2,t2,8
0x2C     0x0003ae03                         lw      t3,0(t2)
0x30     0x001e7e13                         andi    t3,t3,1
0x34     0xfe0e08e3                         bnez    t3,0x24
0x38     0x100003b7                         lui     t2,0x10000
0x3C     0x0063a023                         sw      t1,0(t2)
0x40     0x00128293                         addi    t0,t0,1
0x44     0xfd9ff06f                         j       0x1c
0x48     0x00c12083                         lw      ra,12(sp)
0x4C     0x01010113                         addi    sp,sp,16
0x50     0x00008067                         ret
0x54     "Hello, World!\n\0"                字符串
```

### 程序大小
- 代码段 (.text): 84 字节 (0x00 - 0x53)
- 数据段 (.rodata): 16 字节 (0x54 - 0x63)
- **总计**: 100 字节 (0x64)

---

## 2. 内存布局验证

### 链接脚本定义
```
IRAM:  0x80000000 ~ 0x80003FFF (16KB) - 代码段
DRAM:  0x80004000 ~ 0x80005FFF (8KB)  - 栈
UART:  0x10000000 ~ 0x1000001F       - 外设
```

### 程序实际地址
| 符号 | 地址 | 说明 |
|------|------|------|
| _start | 0x80000000 | 程序入口 |
| main | 0x8000000C | main 函数 |
| hello_str | 0x80000054 | 字符串常量 |
| _stack_top | 0x80006000 | 栈顶 |

**验证**: 所有地址都在 IRAM 范围内 (0x80000000 ~ 0x80003FFF)

---

## 3. UART 寄存器匹配验证

### 程序中的 UART 访问
```assembly
; 状态寄存器检查 (等待 TX 空闲)
lui   t2, 0x10000      ; t2 = 0x10000000
addi  t2, t2, 8        ; t2 = 0x10000008 (UART_STAT)
lw    t3, 0(t2)        ; 读取状态
andi  t3, t3, 1        ; 检查 bit 0 (tx_busy)
bnez  t3, wait         ; tx_busy=1 则等待

; 发送数据
lui   t2, 0x10000      ; t2 = 0x10000000 (UART_TX)
sw    t1, 0(t2)        ; 写入发送数据
```

### SoC 实际 UART 地址映射 (MyRiscV_soc_top.sv:262-274)
```systemverilog
// UART 地址范围：0x10000000 ~ 0x1000001F
wire sel_uart = (dbus_addr[31:12] == 20'h1_0000);

UART u_uart (
    .addr       (dbus_addr[4:0]),  // 取低 5 位
    .wen        (dbus_wen & sel_uart),
    .ren        (dbus_ren & sel_uart),
    .wdata      (dbus_wdata),
    .rdata      (uart_rdata),
    .uart_tx    (uart_tx),
    .uart_rx    (uart_rx)
);
```

### UART 内部寄存器 (uart.sv:27-31, 284-286)
```systemverilog
// 寄存器映射 (addr[4:2])
//   3'b000  TXDATA  0x00  W    [7:0] 写入触发发送
//   3'b001  RXDATA  0x04  R    [31]=有效，[7:0]=数据
//   3'b010  STATUS  0x08  R    [0]=TX 忙，[1]=RX 有数据
//   3'b011  DIVISOR 0x0C  R/W  波特率分频

// STATUS 寄存器输出
3'b010: rdata = {30'd0, rx_valid, tx_busy};  // [0]=tx_busy, [1]=rx_valid
```

**验证结果**:
- UART_TX 地址 0x10000000
- UART_STAT 地址 0x10000008
- tx_busy 在 bit 0 (1=忙，0=空闲)
- **程序逻辑已修正为等待 tx_busy=0**

---

## 4. CPU 取指验证

### 程序入口 (0x80000000)
```systemverilog
// IRAM 地址范围：0x80000000 ~ 0x80003FFF
wire sel_iram = (dbus_addr[31:14] == 18'h2_0000);  // addr[31:14] == 0b10_0000_0000_0000_0000
```

验证 0x80000000:
- 二进制：0b1000_0000_0000_0000_0000_0000_0000_0000
- addr[31:14]: 0b10_0000_0000_0000_0000 = 0x20000

**验证通过**: IRAM 会在 0x80000000 处响应取指

---

## 5. 栈设置验证

### 程序设置
```assembly
lui sp, 0x80006    ; sp = 0x80006000
```

### DRAM 范围
```systemverilog
// DRAM: 0x80004000 ~ 0x80005FFF (8KB)
wire sel_dram = (dbus_addr[31:13] == 19'h4_0002);
```

验证 0x80006000:
- 二进制：0b1000_0000_0000_0000_0110_0000_0000_0000
- addr[31:13]: 0b100_0000_0000_0000_0100 = 0x40002

**验证通过**: 0x80006000 在 DRAM 范围顶部

---

## 6. 关键问题发现与修复

### 问题 1: UART 状态位逻辑反转 (已修复)

**原始代码**:
```assembly
.set UART_TX_READY, 1
beq  t3, zero, wait_tx_ready   ; 等待 bit0=1
```

**问题**: UART 状态寄存器 bit 0 是 `tx_busy` (1=忙)，不是 ready

**修复后**:
```assembly
.set UART_TX_BUSY, 1
bne  t3, zero, wait_tx_ready   ; 等待 tx_busy=0
```

### 问题 2: 程序加载方式

**当前状态**:
- 程序编译为 ELF/BIN 格式
- IRAM 使用 `iram_init.mem` 初始化
- **BIN 文件需要通过 JTAG 加载到 IRAM 或 Flash**

**烧录方案**:
1. **JTAG 直接加载到 IRAM** (调试用):
   ```bash
   openocd -f openocd.cfg -c "load_image helloworld.bin 0x80000000 verify reset"
   ```

2. **烧录到 Flash** (掉电不丢失):
   ```bash
   openocd -f openocd.cfg -c "program helloworld.bin 0x20000000 verify reset"
   ```

---

## 7. 综合路径 vs 仿真路径

### 仿真路径 (`ifndef SYNTHESIS`)
- IRAM 使用 `$readmemh("rtl/perips/iram_init.mem", mem)`
- 组合读，数据立即可用
- 需要将 BIN 转换为 iram_init.mem 格式

### 综合路径 (`ifdef SYNTHESIS`)
- IRAM 使用 8×SDPB (Gowin BSRAM)
- 同步读，数据延迟 1 周期
- cpu_core 有 `iram_wait` 逻辑处理等待

**验证**: cpu_core.sv 的 `iram_wait` 逻辑会在综合路径下自动插入等待周期，程序无需修改

---

## 8. 执行流程追踪

### 上电复位后
1. PC = 0x80000000 (CPU 复位向量)
2. 取指：IRAM[0x80000000] = `lui sp, 0x80006`
3. 执行：sp = 0x80006000 (DRAM 顶部)
4. 跳转：jal ra, main → PC = 0x8000000C

### main 函数执行
1. 保存返回地址：sw ra, 12(sp)
2. 加载字符串地址：la t0, hello_str (0x80000054)
3. 循环:
   - lbu t1, 0(t0)      → 读取字符 'H'
   - 检查 UART busy
   - sw t1, 0x10000000  → UART 发送
   - t0++ → 下一字符
4. 遇到'\0'后返回
5. 死循环 halt

---

## 9. 潜在问题分析

### 问题 A: Flash 烧录后无法直接运行

**原因**: CPU 复位后 PC=0x80000000，从 IRAM 取指
- 如果程序烧录到 Flash (0x20000000)，CPU 不会自动执行

**解决方案**:
1. 烧录 bootloader 到 IRAM 启动区，从 Flash 加载程序
2. 或者通过 JTAG 将程序加载到 IRAM 后直接运行

### 问题 B: IRAM 初始化

**仿真时**:
```bash
# 将 BIN 转换为 hex 格式
./build.sh hex
# 替换 iram_init.mem
cp helloworld.hex rtl/perips/iram_init.mem
# 运行仿真
make sim_soc
```

**综合后**:
- 需要重新综合，将程序固化到 SDPB 初始值
- 或使用 JTAG 动态加载

---

## 10. 结论

### 可执行性判定

| 检查项 | 状态 |
|--------|------|
| 入口地址正确 | 通过 (0x80000000) |
| UART 地址匹配 | 通过 (0x10000000) |
| UART 状态位逻辑 | 已修复 |
| 栈指针设置 | 通过 (0x80006000) |
| 代码大小 | 通过 (100 字节 < 16KB IRAM) |
| 指令集兼容 | 通过 (RV32I 基础指令) |

### 运行方式

**仿真运行**:
```bash
# 1. 生成 hex 文件
./build.sh hex

# 2. 替换初始化文件
cp helloworld.hex rtl/perips/iram_init.mem

# 3. 运行仿真
make sim_soc

# 4. 查看 UART 输出
make wave
```

**实际 FPGA 运行 (JTAG 加载)**:
```bash
# 1. 烧录 bitstream 到 FPGA
make prog

# 2. 通过 JTAG 加载程序
openocd -f openocd.cfg \
  -c "init" \
  -c "halt" \
  -c "load_image helloworld.bin 0x80000000" \
  -c "resume 0x80000000"
```

**预期输出**:
```
Hello, World!
```
通过 UART TX 引脚 @ 115200 8N1 输出

---

## 11. 推荐下一步

1. **仿真验证**: 先用 testbench 验证程序逻辑
2. **JTAG 调试**: 通过 GDB 单步执行确认
3. **固化程序**: 将程序整合到 iram_init.mem 重新综合
