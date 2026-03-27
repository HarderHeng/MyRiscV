/* ============================================================
 * Hello World for MyRiscV
 * 通过 UART 输出 "Hello, World!\n"
 *
 * UART 寄存器地址（轮询模式）：
 *   0x10000000: UART_TX  写数据发送
 *   0x10000004: UART_RX  读数据接收
 *   0x10000008: UART_STAT 状态寄存器
 *
 * 使用汇编直接实现，无 C 依赖
 * ============================================================ */

    .section .text
    .global _start
    .global main
    .type _start, @function
    .type main, @function

/* ============================================================
 * UART 寄存器地址定义
 * ============================================================ */
.set UART_BASE, 0x10000000
.set UART_TX,  0x00    /* 发送寄存器偏移 */
.set UART_STAT, 0x08   /* 状态寄存器偏移 */
.set UART_TX_BUSY,  1  /* 状态位：TX 忙 (1=忙，0=空闲) */

/* ============================================================
 * _start: 入口点，设置栈后跳转到 main
 * ============================================================ */
_start:
    /* 设置栈指针到 DRAM 顶部 (0x80005FFF 向下对齐) */
    li   sp, 0x80006000

    /* 跳转到 main */
    jal  ra, main

    /* main 返回后死循环 */
halt_loop:
    j    halt_loop

_start_end:
    .size _start, _start_end - _start

/* ============================================================
 * main: 输出 Hello, World!
 * ============================================================ */
main:
    /* 保存返回地址 */
    addi sp, sp, -16
    sw   ra, 12(sp)

    /* 加载字符串地址到 t0 */
    la   t0, hello_str

putchar_loop:
    /* 读取字符 */
    lbu  t1, 0(t0)

    /* 遇到 null 终止符则退出 */
    beq  t1, zero, putchar_done

    /* 等待 UART 发送就绪（tx_busy=0 表示空闲） */
wait_tx_ready:
    li   t2, UART_BASE + UART_STAT
    lw   t3, 0(t2)
    andi t3, t3, UART_TX_BUSY
    bne  t3, zero, wait_tx_ready   # tx_busy=1 则继续等待

    /* 发送字符 */
    li   t2, UART_BASE + UART_TX
    sw   t1, 0(t2)

    /* 下一个字符 */
    addi t0, t0, 1
    j    putchar_loop

putchar_done:
    /* 恢复返回地址 */
    lw   ra, 12(sp)
    addi sp, sp, 16

    /* 返回 */
    ret

main_end:
    .size main, main_end - main

/* ============================================================
 * 数据段：Hello World 字符串
 * ============================================================ */
    .section .rodata
hello_str:
    .string "Hello, World!\n"
