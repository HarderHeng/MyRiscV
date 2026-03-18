/* ============================================================
 * 链接脚本：MyRiscV SoC
 * IRAM: 0x80000000 ~ 0x80003FFF (16KB)
 * DRAM: 0x80004000 ~ 0x80005FFF (8KB)
 * ============================================================ */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    IRAM (rx)  : ORIGIN = 0x80000000, LENGTH = 16K
    DRAM (rwx) : ORIGIN = 0x80004000, LENGTH = 8K
}

SECTIONS {
    /* 代码段：放在 IRAM */
    .text : {
        *(.text.start)   /* 启动代码最先，确保 _start 在 0x80000000 */
        *(.text)
        *(.text.*)
        . = ALIGN(4);
    } > IRAM

    /* 只读数据：跟代码段一起放 IRAM */
    .rodata : {
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4);
    } > IRAM

    /* 初始化数据：存储在 IRAM，运行时复制到 DRAM */
    .data : {
        _data_start = .;
        *(.data)
        *(.data.*)
        . = ALIGN(4);
        _data_end = .;
    } > DRAM AT > IRAM

    /* BSS 段：未初始化全局变量，放 DRAM，启动时清零 */
    .bss : {
        _bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DRAM

    /* 栈：DRAM 末尾向下生长（8KB DRAM 顶部） */
    _stack_top = ORIGIN(DRAM) + LENGTH(DRAM);
}
