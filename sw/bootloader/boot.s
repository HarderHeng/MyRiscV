// ============================================================
// Flash Bootloader for MyRiscV
// 上电时从 Flash (0x20000000) 加载程序到 IRAM (0x80000000)
// 然后跳转到 IRAM 执行
// ============================================================
// 使用方法：
// 1. 将 bootloader 编译为 bin
// 2. 将 bootloader + 应用程序合并到 flash_init.mem
// 3. 烧录 bitstream 和 flash_init.mem 到 FPGA
// 4. 上电自动运行

    .section .text.boot
    .global _start
    .type _start, @function

/* ============================================================
 * 地址定义
 * ============================================================ */
.set FLASH_BASE,    0x20000000
.set IRAM_BASE,     0x80000000
.set FLASH_HEADER,  FLASH_BASE
.set IRAM_HEADER,   IRAM_BASE

/* ============================================================
 * _start: 复位入口（0x20000000）
 * ============================================================ */
_start:
    /* 设置临时栈（使用 DRAM） */
    li   sp, 0x80006000

    /* 读取 Flash 头部 */
    li   t0, FLASH_HEADER
    lw   t1, 0(t0)      /* t1 = magic + header_size */
    li   t2, 0x4D525642  /* "MRVB" = MyRiscV Bootloader magic */
    bne  t1, t2, boot_fail  /* magic 不匹配则停机 */

    /* 头部格式：
     *   [31:24] = magic 'M'
     *   [23:16] = magic 'R'
     *   [15:8]  = magic 'V'
     *   [7:0]   = header_size (4)
     *   [31:0] @+4 = program_size (words)
     *   [31:0] @+8 = 程序起始地址 (IRAM)
     */

    /* t3 = 程序大小（字数） */
    lw   t3, 4(t0)
    beqz t3, boot_done    /* 大小=0 则直接跳转 */

    /* t4 = Flash 源地址 (跳过头部) */
    li   t4, FLASH_BASE + 8

    /* t5 = IRAM 目标地址 */
    li   t5, IRAM_BASE

    /* t6 = 结束地址 */
    add  t6, t5, t3
    slli t6, t6, 2        /* 字数 → 字节数 */
    add  t6, t6, t5       /* 这里计算有误，重新计算 */

copy_loop:
    beqz t3, boot_done    /* 计数=0 则完成 */

    /* 从 Flash 读 */
    lw   t7, 0(t4)
    addi t4, t4, 4

    /* 写入 IRAM */
    sw   t7, 0(t5)
    addi t5, t5, 4

    /* 计数递减 */
    addi t3, t3, -1
    j    copy_loop

boot_done:
    /* 跳转到 IRAM 执行 */
    li   t0, IRAM_BASE
    jalr zero, 0(t0)

boot_fail:
    /* 停机（死循环） */
fail_loop:
    j    fail_loop

/* ============================================================
 * 填充到 8 字节对齐
 * ============================================================ */
    .align 3
boot_end:

/* ============================================================
 * 头部信息（链接器会自动放置）
 * ============================================================ */
    .section .header
    .word  0x4D525642      /* Magic: "MRVB" */
    .word  program_size    /* 程序大小（字数） */
    .word  IRAM_BASE        /* 目标地址 */

/* ============================================================
 * 符号定义（由链接器提供）
 * ============================================================ */
    .extern _text_start
    .extern _text_end

    .size _start, . - _start
