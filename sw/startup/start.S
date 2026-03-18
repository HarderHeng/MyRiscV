/* ============================================================
 * 启动代码：_start
 * 初始化 sp，清零 BSS，跳转到 main
 * ============================================================ */
    .section .text.start
    .global _start
    .type _start, @function

_start:
    /* 设置栈指针（指向 DRAM 顶部） */
    la   sp, _stack_top

    /* 清零 BSS 段 */
    la   t0, _bss_start
    la   t1, _bss_end
bss_loop:
    bge  t0, t1, bss_done
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    bss_loop
bss_done:

    /* 调用 main */
    call main

    /* main 返回后死循环 */
halt:
    j    halt

    .size _start, . - _start
