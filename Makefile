PROJ    = myriscv
TOPMOD  = MyRiscV_soc_top

RTL_DIR = rtl
SIM_DIR = sim
SYN_DIR = syn

# include 路径（iverilog 格式：OSS CAD Suite iverilog 使用 -I，不支持 +incdir+）
INCDIRS = -I$(RTL_DIR)/alu -I$(RTL_DIR)/core

# include 路径（Yosys 格式，使用 -I）
INCDIRS_YOSYS = -I$(RTL_DIR)/alu -I$(RTL_DIR)/core

# RTL 源文件列表（仿真和综合共用，使用 IRAM+DRAM）
SIM_SRCS = \
    $(RTL_DIR)/alu/alu.sv \
    $(RTL_DIR)/core/regfile.sv \
    $(RTL_DIR)/core/if.sv \
    $(RTL_DIR)/core/if_id.sv \
    $(RTL_DIR)/core/id.sv \
    $(RTL_DIR)/core/id_ex.sv \
    $(RTL_DIR)/core/ex.sv \
    $(RTL_DIR)/core/ex_mem.sv \
    $(RTL_DIR)/core/mem.sv \
    $(RTL_DIR)/core/mem_wb.sv \
    $(RTL_DIR)/core/hazard.sv \
    $(RTL_DIR)/core/cpu_core.sv \
    $(RTL_DIR)/debug/jtag_dtm.sv \
    $(RTL_DIR)/debug/debug_module.sv \
    $(RTL_DIR)/perips/uart.sv \
    $(RTL_DIR)/perips/iram.sv \
    $(RTL_DIR)/perips/dram.sv \
    $(RTL_DIR)/perips/flash_ctrl.sv \
    $(RTL_DIR)/soc/MyRiscV_soc_top.sv

# RTL 源文件列表（FPGA 综合用，同 SIM_SRCS）
SYN_SRCS = $(SIM_SRCS)

SIM_OUT_DIR = $(SIM_DIR)/out
$(shell mkdir -p $(SIM_OUT_DIR))

# -------------------------------------------------------
# 仿真目标（Phase 1 主目标）
# -------------------------------------------------------

.PHONY: sim_alu sim_soc clean help

sim_alu: $(SIM_OUT_DIR)/tb_alu
	@echo "=== Running ALU simulation ==="
	vvp $<

$(SIM_OUT_DIR)/tb_alu: $(RTL_DIR)/alu/alu.sv $(SIM_DIR)/tb/tb_alu.sv
	iverilog -g2012 $(INCDIRS) -o $@ $^

# SoC 级仿真（主目标：验证 CPU 执行 Hello!\n）
sim_soc: $(SIM_OUT_DIR)/tb_soc
	@echo "=== Running SoC simulation ==="
	vvp $<

$(SIM_OUT_DIR)/tb_soc: $(SIM_SRCS) $(SIM_DIR)/tb/tb_soc.sv
	iverilog -g2012 $(INCDIRS) -o $@ $^

# 查看波形（需要 gtkwave）
wave:
	gtkwave $(SIM_OUT_DIR)/tb_soc.vcd &

# -------------------------------------------------------
# 综合目标（OSS CAD Suite，Phase 2）
# -------------------------------------------------------

.PHONY: synth pnr bitstream prog

synth: $(SYN_DIR)/out/$(PROJ).json

$(SYN_DIR)/out/$(PROJ).json: $(SYN_SRCS)
	@mkdir -p $(SYN_DIR)/out
	yosys -p "verilog_defaults -add -I$(RTL_DIR)/alu -I$(RTL_DIR)/core -DSYNTHESIS; \
	    read_verilog -sv $^; \
	    synth_gowin -top $(TOPMOD) -json $@"

pnr: $(SYN_DIR)/out/$(PROJ)_pnr.json

$(SYN_DIR)/out/$(PROJ)_pnr.json: $(SYN_DIR)/out/$(PROJ).json $(SYN_DIR)/constraints/$(PROJ).pcf
	nextpnr-gowin \
	    --json $< \
	    --write $@ \
	    --device GW1NR-LV9QN88PC6/I5 \
	    --family GW1N-9C \
	    --pcf $(SYN_DIR)/constraints/$(PROJ).pcf

bitstream: $(SYN_DIR)/out/$(PROJ).fs

$(SYN_DIR)/out/$(PROJ).fs: $(SYN_DIR)/out/$(PROJ)_pnr.json
	gowin_pack --device GW1NR-LV9QN88PC6/I5 --input $< --output $@

prog: $(SYN_DIR)/out/$(PROJ).fs
	openFPGALoader -b tangnano9k $<

# -------------------------------------------------------
# 软件编译（交叉工具链，Phase 2）
# -------------------------------------------------------

RISCV_CC    = riscv32-unknown-elf-gcc
RISCV_FLAGS = -march=rv32i -mabi=ilp32 -nostdlib -T sw/linker/link.ld

.PHONY: sw_test sw_disasm

sw_test:
	$(RISCV_CC) $(RISCV_FLAGS) -o sw/test/test.elf sw/startup/start.S sw/test/test.c
	riscv32-unknown-elf-objcopy -O binary sw/test/test.elf sw/test/test.bin

sw_disasm: sw/test/test.elf
	riscv32-unknown-elf-objdump -d $< | head -80

# -------------------------------------------------------
# 清理
# -------------------------------------------------------

clean:
	rm -rf $(SIM_OUT_DIR) $(SYN_DIR)/out

help:
	@echo "Phase 1 仿真："
	@echo "  make sim_soc    — 编译并运行 SoC 仿真（验证 Hello!\\n）"
	@echo "  make sim_alu    — 编译并运行 ALU 单元测试"
	@echo "  make wave       — 打开 GTKWave 查看波形"
	@echo ""
	@echo "Phase 2 综合："
	@echo "  make synth      — Yosys 综合，生成 .json"
	@echo "  make pnr        — nextpnr-gowin 布局布线"
	@echo "  make bitstream  — 打包比特流 .fs"
	@echo "  make prog       — 烧录到 Tang Nano 9K"
	@echo ""
	@echo "清理："
	@echo "  make clean      — 删除所有生成文件"
