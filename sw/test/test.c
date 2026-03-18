/* ============================================================
 * 测试程序：输出 "Hello!\n" 到 UART
 * UART 基址：0x10000000
 *   TXDATA  +0x00  写字节发送
 *   RXDATA  +0x04  读字节接收
 *   STATUS  +0x08  [0]=TX忙, [1]=RX有数据
 *   DIVISOR +0x0C  波特率分频（默认234=27MHz/115200）
 * ============================================================ */

#define UART_BASE  0x10000000
#define UART_TX    0x00
#define UART_STATUS 0x08

/* 等待 TX 空闲，然后发送一个字节 */
static void uart_putc(volatile unsigned int *uart, char c)
{
    volatile unsigned int *status = (volatile unsigned int *)
        ((unsigned int)uart + UART_STATUS);
    volatile unsigned int *txdata = (volatile unsigned int *)
        ((unsigned int)uart + UART_TX);

    /* 轮询等待 TX 不忙（STATUS[0]=0） */
    while (*status & 1)
        ;

    /* 写入发送寄存器 */
    *txdata = (unsigned int)(unsigned char)c;
}

int main(void)
{
    volatile unsigned int *uart = (volatile unsigned int *)UART_BASE;
    const char *msg = "Hello!\n";
    const char *p;

    for (p = msg; *p; p++) {
        uart_putc(uart, *p);
    }

    /* 死循环 */
    while (1)
        ;

    return 0;
}
