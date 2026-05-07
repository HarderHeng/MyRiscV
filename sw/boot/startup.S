# RISC-V Bootloader Startup Code
# Linked to IRAM at 0x80000000

.section .text.startup
.global _start

_start:
    # Set stack pointer to top of DRAM
    lui sp, %hi(0x80006000)
    ori sp, sp, %lo(0x80006000)

    # Zero .bss section
    la a0, _bss_start
    la a1, _bss_end
    bgeu a0, a1, 2f
1:
    sw zero, 0(a0)
    addi a0, a0, 4
    bltu a0, a1, 1b
2:

    # Call main
    jal ra, main

    # If main returns, loop forever
loop:
    j loop

# Dummy handler for unhandled interrupts
.global _trap
_trap:
    j _trap
