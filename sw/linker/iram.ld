/* Linker script for MyRiscV - IRAM version
 * All code and data linked to internal SRAM at 0x80000000
 */

ENTRY(_start)

MEMORY {
    /* IRAM - 16KB at 0x80000000 */
    IRAM (rxw) : ORIGIN = 0x80000000, LENGTH = 16K

    /* DRAM - 8KB at 0x80004000 (for stack) */
    DRAM (rwx) : ORIGIN = 0x80004000, LENGTH = 8K
}

SECTIONS {
    /* Code goes to IRAM */
    .text 0x80000000 : {
        _start = .;
        *(.text.startup)
        *(.text)
        *(.text.*)
        . = ALIGN(4);
    } > IRAM

    .rodata : {
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4);
    } > IRAM

    /* Small data goes to IRAM */
    .sdata : {
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4);
    } > IRAM

    /* Static data goes to DRAM */
    .data : {
        _data_start = .;
        *(.data)
        *(.data.*)
        . = ALIGN(4);
        _edata = .;
    } > DRAM AT > IRAM

    /* BSS goes to DRAM */
    .bss : {
        _bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
        _end = .;
    } > DRAM

    /* Stack at top of DRAM */
    .stack (NOLOAD) : {
        . = ALIGN(16);
        _stack_bottom = .;
        . = . + 0x800;      /* 2KB stack */
        _stack_top = .;
    } > DRAM
}
