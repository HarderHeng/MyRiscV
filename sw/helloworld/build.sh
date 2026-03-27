#!/bin/bash
# ============================================================
# Hello World for MyRiscV - 构建脚本
# ============================================================
# 用法：
#   ./build.sh          - 编译并生成 helloworld.bin
#   ./build.sh disasm   - 反汇编查看
#   ./build.sh clean    - 清理
# ============================================================

set -e

# 工具链前缀（使用 riscv64-unknown-elf-gcc，编译 rv32i 程序）
RISCV_PREFIX="riscv64-unknown-elf-"

# 编译选项
CC="${RISCV_PREFIX}gcc"
OBJCOPY="${RISCV_PREFIX}objcopy"
OBJDUMP="${RISCV_PREFIX}objdump"
SIZE="${RISCV_PREFIX}size"

# 文件
SRC="helloworld.s"
ELF="helloworld.elf"
BIN="helloworld.bin"
HEX="helloworld.hex"
LD="link.ld"

# 编译标志
CFLAGS="-march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -nostartfiles"
CFLAGS+=" -Wl,-T,${LD}"
CFLAGS+=" -Wl,-Map=helloworld.map"

case "${1:-}" in
    clean)
        echo "Cleaning..."
        rm -f ${ELF} ${BIN} ${HEX} ${ELF}.map
        echo "Done."
        ;;

    disasm)
        if [ ! -f ${ELF} ]; then
            echo "Error: ${ELF} not found. Run './build.sh' first."
            exit 1
        fi
        echo "=== Disassembly of ${ELF} ==="
        ${OBJDUMP} -d ${ELF} | head -100
        echo ""
        echo "=== Symbol Table ==="
        ${OBJDUMP} -t ${ELF} | head -30
        ;;

    hex)
        if [ ! -f ${BIN} ]; then
            echo "Error: ${BIN} not found. Run './build.sh' first."
            exit 1
        fi
        echo "=== Generating HEX file ==="
        # 生成 Verilog 可用的 hex 文件（用于 IRAM 初始化）
        ${RISCV_PREFIX}hexdump ${BIN} > ${HEX}
        echo "Generated: ${HEX}"
        ;;

    "")
        echo "=== Building Hello World for MyRiscV ==="
        echo ""

        # 检查源文件
        if [ ! -f ${SRC} ]; then
            echo "Error: Source file ${SRC} not found!"
            exit 1
        fi

        if [ ! -f ${LD} ]; then
            echo "Error: Linker script ${LD} not found!"
            exit 1
        fi

        # 编译链接
        echo "[1/3] Compiling ${SRC}..."
        ${CC} ${CFLAGS} -o ${ELF} ${SRC}

        # 生成二进制
        echo "[2/3] Generating ${BIN}..."
        ${OBJCOPY} -O binary ${ELF} ${BIN}

        # 显示大小
        echo "[3/3] Size info:"
        ${SIZE} -A ${ELF}
        echo ""

        echo "=== Build Successful ==="
        echo "Output files:"
        echo "  - ${ELF}  (ELF 可执行文件)"
        echo "  - ${BIN}  (二进制文件，可用于烧录)"
        echo "  - helloworld.map (内存映射)"
        echo ""
        echo "Next steps:"
        echo "  - ./build.sh disasm  : 查看反汇编"
        echo "  - ./build.sh hex     : 生成 hex 文件（用于 IRAM 仿真）"
        echo "  - openocd + gdb      : 通过 JTAG 烧录到 Flash"
        ;;

    *)
        echo "Usage: $0 [clean|disasm|hex]"
        echo ""
        echo "  (no arg)  - Build helloworld.bin"
        echo "  disasm    - Disassemble the ELF file"
        echo "  hex       - Generate hex file for IRAM init"
        echo "  clean     - Remove generated files"
        ;;
esac
