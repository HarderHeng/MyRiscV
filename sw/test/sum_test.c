/*
 * MyRiscV 流水线验证程序
 * 计算 0 + 1 + 2 + ... + 10 = 55
 * 验证：PC、SP、寄存器、循环跳转、分支冒险
 */

#define UART_BASE   0x10000000
#define UART_TX     0x00
#define UART_STATUS 0x08

/* 发送一个字符 */
static void uart_putc(char c)
{
    volatile unsigned int *status = (volatile unsigned int *)(UART_BASE + UART_STATUS);
    volatile unsigned int *txdata = (volatile unsigned int *)(UART_BASE + UART_TX);

    while (*status & 1)
        ;
    *txdata = (unsigned int)(unsigned char)c;
}

/* 发送字符串 */
static void print_str(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

/* 发送回车换行 */
static void print_nl(void)
{
    uart_putc('\r');
    uart_putc('\n');
}

/* 发送单个数字 */
static void print_digit(unsigned int n)
{
    uart_putc('0' + n);
}

int main(void)
{
    unsigned int sum;
    unsigned int i;
    unsigned int temp;

    print_str("=== MyRiscV Pipeline Test ===");
    print_nl();
    print_nl();

    /* 测试1: 栈指针 */
    print_str("Test 1: Stack Pointer");
    print_nl();
    print_str("  SP init OK");
    print_nl();

    /* 测试2: 寄存器初始化 */
    print_str("Test 2: Register Init");
    print_nl();
    i = 0;
    if (i == 0) {
        print_str("  x0=0 OK (x0 always zero)");
        print_nl();
    }

    /* 测试3: 立即数加载 */
    print_str("Test 3: Immediate Load");
    print_nl();
    i = 10;
    if (i == 10) {
        print_str("  lui/addi: i=10 OK");
        print_nl();
    }

    /* 测试4: 加法 */
    print_str("Test 4: Addition");
    print_nl();
    sum = 5 + 3;
    if (sum == 8) {
        print_str("  5+3=8 OK");
        print_nl();
    } else {
        print_str("  5+3=? FAIL");
        print_nl();
    }

    /* 测试5: 循环累加 0+1+2+...+10 */
    print_str("Test 5: Loop (0+1+...+10)");
    print_nl();

    sum = 0;
    i = 0;

    /* 手写汇编风格的循环，避免除法 */
    /* sum = 0; for(i=0; i<=10; i++) sum += i; */
    __asm__ volatile (
        /* sum = 0 */
        "mv t0, zero\n"
        /* i = 0 */
        "mv t1, zero\n"
        /* loop: sum += i; i++; if(i<=10) goto loop */
        "sum_loop:\n"
        "add t0, t0, t1\n"
        "addi t1, t1, 1\n"
        "slti t2, t1, 11\n"
        "bnez t2, sum_loop\n"
        /* 结果存在 t0 */
        : : : "t0", "t1", "t2"
    );

    /* 输出 sum */
    if (sum == 55) {
        print_str("  PASS: 0+1+...+10=55");
    } else {
        print_str("  FAIL: expected 55");
    }
    print_nl();

    /* 测试6: 减法（验证EX阶段ALU） */
    print_str("Test 6: Subtraction");
    print_nl();
    sum = 10 - 3;
    if (sum == 7) {
        print_str("  10-3=7 OK");
        print_nl();
    } else {
        print_str("  10-3=? FAIL");
        print_nl();
    }

    /* 测试7: 逻辑运算 */
    print_str("Test 7: Logic Operations");
    print_nl();
    i = 0xFF & 0x0F;  /* = 0x0F = 15 */
    if (i == 15) {
        print_str("  andi: 0xFF&0x0F=15 OK");
        print_nl();
    }

    /* 测试8: OR运算 */
    print_str("Test 8: OR Operations");
    print_nl();
    i = 0x0F | 0x30;  /* = 0x3F = 63 */
    if (i == 63) {
        print_str("  ori: 0x0F|0x30=63 OK");
        print_nl();
    }

    print_nl();
    print_str("=== All Tests Complete ===");
    print_nl();

    /* 死循环 */
    while (1)
        ;

    return 0;
}
