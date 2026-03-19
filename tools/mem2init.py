#!/usr/bin/env python3
"""
mem2init.py — 将 iram_init.mem（4096 行 × 32bit hex）转换为
8 个 SDPB bank 的 INIT_RAM_xx 参数，写入 iram_init_params.vh

使用方法：
    python3 tools/mem2init.py rtl/perips/iram_init.mem

输出：
    rtl/perips/iram_init_params.vh

SDPB 32bit 模式参数映射：
  - IRAM 有 4096 个 32bit 字，按 word_addr[11:9] 分为 8 个 bank（bank 0~7）
  - 每个 bank 有 512 个字（word_addr[8:0]）
  - 每个 SDPB 有 64 个 INIT_RAM_xx 参数（INIT_RAM_00 ~ INIT_RAM_3F）
  - 每个 INIT_RAM_xx = 256bit = 8 个 32bit 字
  - 因此每个 bank 共 64 × 8 = 512 字，正好对应一个 SDPB
"""

import sys
import os

def main():
    if len(sys.argv) < 2:
        print("用法: python3 tools/mem2init.py <iram_init.mem>", file=sys.stderr)
        sys.exit(1)

    mem_file = sys.argv[1]
    out_file = os.path.join(os.path.dirname(mem_file), "iram_init_params.vh")

    # 读取 .mem 文件（4096 行，每行 8 个十六进制字符 = 32bit）
    words = []
    with open(mem_file, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("//") and not line.startswith("#"):
                words.append(int(line, 16))

    if len(words) != 4096:
        print(f"错误：期望 4096 行，实际读到 {len(words)} 行", file=sys.stderr)
        sys.exit(1)

    # 生成每个 bank 的 INIT_RAM 参数
    # bank i 对应 word_addr[11:9] == i，即 words[i*512 : (i+1)*512]
    lines = []
    lines.append("// 自动生成，请勿手动编辑")
    lines.append("// 由 tools/mem2init.py 从 rtl/perips/iram_init.mem 生成")
    lines.append("")

    for bank in range(8):
        bank_words = words[bank * 512 : (bank + 1) * 512]
        lines.append(f"// ===== Bank {bank} (BLK_SEL = 3'd{bank}) =====")

        # 64 个 INIT_RAM_xx 参数，每个 256bit = 8 个 32bit 字
        for param_idx in range(64):
            chunk = bank_words[param_idx * 8 : (param_idx + 1) * 8]
            # INIT_RAM 字节序：低地址字在低比特位（小端拼接）
            # 256bit = 8 words，word[0] 在 bits[31:0]，word[7] 在 bits[255:224]
            val = 0
            for word_i, w in enumerate(chunk):
                val |= (w & 0xFFFFFFFF) << (word_i * 32)
            param_name = f"INIT_RAM_{param_idx:02X}"
            # 格式化为 256bit 十六进制（64 个十六进制字符）
            hex_str = f"{val:064X}"
            lines.append(f"    parameter {param_name} = 256'h{hex_str},")

        lines.append("")

    # 写入输出文件
    with open(out_file, "w") as f:
        f.write("\n".join(lines))
        f.write("\n")

    print(f"已生成 {out_file}（{8} 个 bank × 64 参数）")

if __name__ == "__main__":
    main()
