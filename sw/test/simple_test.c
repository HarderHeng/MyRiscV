/*
 * 最简单的 C 测试程序
 */

#define UART_BASE  0x10000000
#define UART_TX    0x00
#define UART_STATUS 0x08

static void uart_putc(char c)
{
    volatile unsigned int *status = (volatile unsigned int *)(UART_BASE + UART_STATUS);
    volatile unsigned int *txdata = (volatile unsigned int *)(UART_BASE + UART_TX);
    while (*status & 1)
        ;
    *txdata = (unsigned int)(unsigned char)c;
}

static void print_str(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

int main(void)
{
    print_str("OK\n");
    while (1)
        ;
    return 0;
}
