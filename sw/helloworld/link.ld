/* ============================================================
 * 链接脚本：MyRiscV Hello World (Flash 启动)
 * FLASH: 0x20000000 ~ 0x2012FFFF (76KB) - 代码/只读数据
 * DRAM:  0x80004000 ~ 0x80005FFF (8KB)  - 数据/栈
 * ============================================================ */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    FLASH (rx)  : ORIGIN = 0x20000000, LENGTH = 76K
    DRAM  (rwx) : ORIGIN = 0x80004000, LENGTH = 8K
}

SECTIONS {
    /* 代码段：放在 Flash */
    .text : {
        *(.text)
        *(.text.*)
        . = ALIGN(4);
    } > FLASH

    /* 只读数据：跟代码段一起放 Flash */
    .rodata : {
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4);
    } > FLASH

    /* 初始化数据：存储在 Flash，运行时复制到 DRAM */
    .data : {
        _data_start = .;
        *(.data)
        *(.data.*)
        . = ALIGN(4);
        _data_end = .;
    } > DRAM AT > FLASH

    /* BSS 段：未初始化全局变量，放 DRAM，启动时清零 */
    .bss : {
        _bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DRAM

    /* 栈指针位置：DRAM 顶部 */
    _stack_top = ORIGIN(DRAM) + LENGTH(DRAM);

    /* 加载地址（用于.data 段复制） */
    _data_loadaddr = LOADADDR(.data);
}
