#!/usr/bin/env python3
"""
bin2flash.py - 将 RISC-V bin 文件转换为 MyRiscV Flash 初始化文件

用法：
    ./bin2flash.py input.bin output.mem

格式说明：
    - 输入：纯二进制文件（小端 32 位字）
    - 输出：Verilog $readmemh 格式（每行 8 位 hex，4 行组成 1 个 32 位字）
"""

import sys
import os

def bin2flash(bin_file, mem_file):
    # 读取 bin 文件
    with open(bin_file, 'rb') as f:
        data = f.read()

    # 填充到 4 字节对齐
    padding = (4 - len(data) % 4) % 4
    if padding > 0:
        data += b'\x00' * padding

    # 生成 Flash init 文件
    # Flash 控制器按 32 位字寻址，每行一个字（8 位 hex）
    with open(mem_file, 'w') as f:
        f.write("// MyRiscV Flash 初始化文件\n")
        f.write(f"// 源文件：{os.path.basename(bin_file)}\n")
        f.write(f"// 大小：{len(data)} 字节 ({len(data)//4} 字)\n")
        f.write("// 地址：0x20000000\n")
        f.write("//\n")
        f.write("// 格式：每行一个 32 位字（8 位十六进制，大端显示）\n")
        f.write("//\n\n")

        # 每 16 个字（64 字节）为一组显示
        words_per_line = 16
        word_count = len(data) // 4

        for i in range(0, word_count, words_per_line):
            addr = i * 4
            f.write(f"// 0x{addr:06X}:\n")
            for j in range(words_per_line):
                idx = i + j  # 字索引
                if idx < word_count:
                    # 小端转换为大端显示
                    word = data[idx*4:(idx+1)*4]
                    val = int.from_bytes(word, 'little')
                    f.write(f"{val:08X}\n")
                else:
                    f.write("00000000\n")

        # 填充剩余空间到最大容量（可选，32K 字）
        # f.write("\n// 填充剩余空间 (NOP)\n")
        # for i in range(word_count, 32768):
        #     f.write("00000000\n")

    print(f"转换完成：{bin_file} -> {mem_file}")
    print(f"  - 程序大小：{len(data)} 字节 ({word_count} 字)")
    print(f"  - Flash 起始地址：0x20000000")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("用法：./bin2flash.py <input.bin> <output.mem>")
        print("示例：./bin2flash.py helloworld.bin flash_init.mem")
        sys.exit(1)

    bin2flash(sys.argv[1], sys.argv[2])
