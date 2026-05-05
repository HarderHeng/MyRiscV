/* ============================================================
 * MyRiscV 流水线验证程序 - 纯汇编版
 * 计算 0+1+2+...+10 = 55 并输出结果
 * ============================================================ */

#define UART_BASE  0x10000000
#define UART_TX    0x00
#define UART_STAT  0x08

    .section .text.start
    .global _start
    .type _start, @function

_start:
    /* 设置栈指针 */
    lui  sp, 0x80006          # sp = 0x80006000

    /* 清零 BSS 段 */
    la   t0, _bss_start
    la   t1, _bss_end
bss_loop:
    bgeu t0, t1, bss_done
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    bss_loop
bss_done:

    /* 调用 main */
    call main

    /* main 返回后死循环 */
halt:
    j    halt

/* ============================================================
 * main: 计算并输出结果
 * ============================================================ */
    .text
    .global main
    .type main, @function

main:
    /* 保存返回地址 */
    addi sp, sp, -16
    sw   ra, 12(sp)

    /* 打印标题 */
    la   a0, msg_title
    call print_str
    call print_nl

    /* 打印 Test 1 */
    la   a0, msg_test1
    call print_str
    call print_nl

    /* 打印结果 */
    la   a0, msg_sum
    call print_str
    mv   a0, s0           /* 结果已在 s0 */
    call print_num
    call print_nl

    /* 恢复并返回 */
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

/* ============================================================
 * print_str: 打印字符串
 * a0 = 字符串地址
 * ============================================================ */
print_str:
    /* 保存调用者保存的寄存器 */
    addi sp, sp, -16
    sw   s0, 8(sp)
    sw   ra, 12(sp)
    mv   s0, a0

ps_loop:
    lbu  a1, 0(s0)
    beq  a1, zero, ps_done
    call uart_putc
    addi s0, s0, 1
    j    ps_loop
ps_done:
    lw   s0, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

/* ============================================================
 * print_num: 打印无符号数字 (仅支持 0-99)
 * a0 = 数字
 * ============================================================ */
print_num:
    /* 简化版：直接输出数字的 ASCII */
    addi a1, a0, 0
    call uart_putc
    ret

/* ============================================================
 * print_nl: 打印换行
 * ============================================================ */
print_nl:
    li   a0, 13
    call uart_putc
    li   a0, 10
    call uart_putc
    ret

/* ============================================================
 * uart_putc: 发送一个字符
 * a0 = 字符
 * ============================================================ */
uart_putc:
    /* 等待 TX 空闲 */
    lui  t0, 0x10000
    lw   t1, UART_STAT(t0)
    andi t1, t1, 1
    bnez t1, uart_putc
    /* 发送字符 */
    sw   a0, UART_TX(t0)
    ret

/* ============================================================
 * main 函数真正的实现
 * 使用内联汇编计算 0+1+2+...+10 = 55
 * ============================================================ */
    .global compute_sum
    .type compute_sum, @function

compute_sum:
    /* 使用内联汇编计算 */
    li   s0, 0         /* sum = 0 */
    li   t0, 0         /* i = 0 */
sum_loop:
    add  s0, s0, t0    /* sum += i */
    addi t0, t0, 1     /* i++ */
    slti t1, t0, 11    /* i < 11? */
    bnez t1, sum_loop  /* 如果 true, 继续循环 */
    /* 结果在 s0, 应该是 55 */
    ret

/* ============================================================
 * 修改 main 直接调用 compute_sum
 * ============================================================ */
main:
    addi sp, sp, -16
    sw   ra, 12(sp)

    /* 调用 compute_sum */
    call compute_sum

    /* 打印结果 */
    la   a0, msg_result
    call print_str
    mv   a0, s0
    call print_num
    call print_nl

    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

/* ============================================================
 * 数据段
 * ============================================================ */
    .section .rodata
msg_title:
    .string "=== MyRiscV Pipeline Test ==="
msg_test1:
    .string "Test: 0+1+...+10"
msg_result:
    .string "Sum = "
