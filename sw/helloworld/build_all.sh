#!/bin/bash
# ============================================================
# MyRiscV Hello World - 完整构建和烧录脚本
# ============================================================
# 用法：
#   ./build_all.sh          - 编译 + 生成所有格式
#   ./build_all.sh flash    - 通过 JTAG 烧录到 Flash
#   ./build_all.sh sim      - 生成仿真用的 hex 文件
#   ./build_all.sh clean    - 清理
# ============================================================

set -e

# 工具链
RISCV_PREFIX="riscv64-unknown-elf-"
CC="${RISCV_PREFIX}gcc"
OBJCOPY="${RISCV_PREFIX}objcopy"
OBJDUMP="${RISCV_PREFIX}objdump"
SIZE="${RISCV_PREFIX}size"

# 文件
SRC="helloworld.s"
ELF="helloworld.elf"
BIN="helloworld.bin"
HEX="helloworld.hex"
MEM="helloworld.mem"
LD="link.ld"
OPENOCD_CFG="openocd.cfg"

# 编译标志
CFLAGS="-march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -nostartfiles"
CFLAGS+=" -Wl,-T,${LD}"
CFLAGS+=" -Wl,-Map=helloworld.map"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

build() {
    log_info "=== 构建 Hello World for MyRiscV ==="
    echo ""

    # 检查源文件
    if [ ! -f "${SRC}" ]; then
        log_error "源文件 ${SRC} 未找到!"
        exit 1
    fi

    if [ ! -f "${LD}" ]; then
        log_error "链接脚本 ${LD} 未找到!"
        exit 1
    fi

    # 编译链接
    log_info "[1/4] 编译 ${SRC}..."
    ${CC} ${CFLAGS} -o ${ELF} ${SRC}

    # 生成二进制
    log_info "[2/4] 生成 ${BIN}..."
    ${OBJCOPY} -O binary ${ELF} ${BIN}

    # 生成 hex 文件（用于 Verilog $readmemh）
    log_info "[3/4] 生成 ${HEX}..."
    ${OBJCOPY} -O verilog ${ELF} ${HEX}

    # 生成 mem 文件（用于 IRAM 初始化，带地址）
    log_info "[4/4] 生成 ${MEM}..."
    ${OBJDUMP} -h ${ELF} > ${MEM}.dump
    ${OBJDUMP} -d ${ELF} >> ${MEM}.dump

    # 显示大小
    echo ""
    ${SIZE} -A ${ELF}
    echo ""

    log_info "=== 构建成功 ==="
    echo ""
    echo "输出文件:"
    echo "  - ${ELF}   : ELF 可执行文件（用于调试）"
    echo "  - ${BIN}   : 纯二进制（用于 JTAG 烧录）"
    echo "  - ${HEX}   : Verilog hex 格式（用于仿真）"
    echo "  - ${MEM}.dump : 反汇编输出"
    echo ""
    echo "程序信息:"
    echo "  - 入口地址：0x80000000 (IRAM)"
    echo "  - 输出：UART TX @ 0x10000000"
    echo "  - 字符串：\"Hello, World!\\n\""
    echo ""
}

flash_jtag() {
    log_info "=== 通过 JTAG 烧录到 Flash ==="
    echo ""

    if [ ! -f "${BIN}" ]; then
        log_error "${BIN} 未找到！请先运行 './build_all.sh build'"
        exit 1
    fi

    if [ ! -f "${OPENOCD_CFG}" ]; then
        log_error "${OPENOCD_CFG} 未找到!"
        exit 1
    fi

    # Flash 目标地址（片上 Flash 起始）
    FLASH_ADDR="0x20000000"

    log_info "烧录 ${BIN} 到 Flash @ ${FLASH_ADDR}"
    log_warn "请确保:"
    echo "  1. Tang Nano 9K 已连接"
    echo "  2. JTAG 适配器已正确接线"
    echo "  3. 已修改 openocd.cfg 以匹配你的硬件"
    echo ""

    openocd -f ${OPENOCD_CFG} \
        -c "program ${BIN} ${FLASH_ADDR} verify reset exit"
}

sim_hex() {
    log_info "=== 生成仿真用 hex 文件 ==="

    if [ ! -f "${ELF}" ]; then
        log_error "${ELF} 未找到！请先运行 './build_all.sh build'"
        exit 1
    fi

    # 生成带地址的 hex 文件（Verilog $readmemh 格式）
    ${OBJCOPY} -O verilog ${ELF} ${HEX}

    log_info "生成 ${HEX}"
    echo ""
    log_info "在仿真中使用："
    echo '  $readmemh("helloworld.hex", mem_array, 32'\''h80000000 >> 2);'
}

clean() {
    log_info "清理..."
    rm -f ${ELF} ${BIN} ${HEX} ${MEM} ${MEM}.dump helloworld.map
    log_info "Done."
}

disasm() {
    if [ ! -f "${ELF}" ]; then
        log_error "${ELF} 未找到！"
        exit 1
    fi

    echo "=== 反汇编 ==="
    ${OBJDUMP} -d ${ELF} | head -80
    echo ""
    echo "=== 符号表 ==="
    ${OBJDUMP} -t ${ELF} | grep -E "^[0-9a-f]+ [gl]" | head -20
}

case "${1:-build}" in
    build)
        build
        ;;
    flash)
        flash_jtag
        ;;
    sim|hex)
        sim_hex
        ;;
    disasm|dump)
        disasm
        ;;
    clean)
        clean
        ;;
    all)
        build
        disasm
        ;;
    *)
        echo "用法：$0 [build|flash|sim|disasm|clean|all]"
        echo ""
        echo "  build   - 编译生成 ELF/BIN/HEX (默认)"
        echo "  flash   - 通过 JTAG 烧录到 Flash"
        echo "  sim     - 生成仿真用 hex 文件"
        echo "  disasm  - 反汇编 ELF 文件"
        echo "  clean   - 删除生成的文件"
        echo "  all     - build + disasm"
        ;;
esac
