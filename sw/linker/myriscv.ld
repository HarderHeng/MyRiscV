/* Linker script for MyRiscV */
/* Memory layout for TangNano-9K */

MEMORY {
    FLASH (rx) : ORIGIN = 0x20000000, LENGTH = 76K
    IRAM  (rwx): ORIGIN = 0x80000000, LENGTH = 16K
    DRAM  (rwx): ORIGIN = 0x80004000, LENGTH = 8K
}

ENTRY(_start)

SECTIONS {
    .text : {
        _start = .;
        *(.text)
        *(.text.*)
    } > FLASH

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    } > FLASH

    .data : {
        _data_start = .;
        *(.data)
        *(.data.*)
    } > DRAM AT > FLASH

    _edata = .;

    .bss : {
        _bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > DRAM

    _end = .;

    .stack : {
        . = ALIGN(16);
        _stack_bottom = .;
        . = . + 0x1000;  /* 4KB stack */
        _stack_top = .;
    } > DRAM
}
