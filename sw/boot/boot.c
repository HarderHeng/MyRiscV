// MyRiscV Bootloader & Hello World
// Linked to IRAM at 0x80000000

// UART registers
#define UART_TX      (*(volatile unsigned int *)0x10000000)
#define UART_STATUS  (*(volatile unsigned int *)0x10000008)

// Global message string
const char message[] = "Hello, World!\n";

// Simple delay loop
static void delay(unsigned int count) {
    while (count-- > 0) {
        __asm__ volatile("nop");
    }
}

// Main entry point
void main(void) {
    const char *p;
    unsigned int i;

    while (1) {
        // Point to message
        p = message;

        // Send characters until null terminator
        while (*p != '\0') {
            // Wait for TX ready (bit 0 = busy)
            while (UART_STATUS & 1) { }
            // Send character
            UART_TX = *p;
            p++;
        }

        // Simple delay ~5 seconds at 27MHz
        // Each iteration takes ~4 cycles, so 27M/4 * 5 = ~33M iterations
        for (i = 0; i < 34000000; i++) {
            __asm__ volatile("nop");
        }
    }
}
