# Makefile for MyRiscV FPGA Softcore
#

PROJECT = myriscv
TOP_MODULE = top
DEVICE = GW1NR-LV9QN88PC6/I5

# Directories
RTL_DIR = rtl
BUILD_DIR = build
SYN_DIR = syn
CONSTRAINTS_DIR = constraints

# Source files
RTL_SOURCES = $(shell find $(RTL_DIR) -name "*.sv" -o -name "*.v" | sort)

# Gowin tools
GOWIN_BIN = /opt/gowin
GW_DELETER = $(GOWIN_BIN)/IDE/bin/gw_deLETER
GW_PACKAGER = $(GOWIN_BIN)/IDE/bin/gw_packager
GW_WRITER = $(GOWIN_BIN)/IDE/bin/gw_writer
PNR = $(GOWIN_BIN)/pnr/bin/nextpnr-gowin

# Default target
.PHONY: all
all: bitstream

# Build gate-level simulation
.PHONY: sim
sim: $(BUILD_DIR)/$(PROJECT)_syn.v

# Synthesis
$(BUILD_DIR)/$(PROJECT)_syn.v: $(RTL_SOURCES)
	@mkdir -p $(BUILD_DIR)
	@echo "=== Running Yosys synthesis ==="
	yosys -p "read_verilog -sv $(RTL_SOURCES); synth_gowin -top $(TOP_MODULE); write_verilog $@"

# Place and route
$(BUILD_DIR)/$(PROJECT)_pnr.json: $(BUILD_DIR)/$(PROJECT)_syn.v $(CONSTRAINTS_DIR)/$(PROJECT).pcf
	@mkdir -p $(BUILD_DIR)
	@echo "=== Running nextpnr ==="
	$(PNR) --device $(DEVICE) --json $(BUILD_DIR)/$(PROJECT).json --pcf $(CONSTRAINTS_DIR)/$(PROJECT).pcf --write $@

# Bitstream
$(BUILD_DIR)/$(PROJECT).fs: $(BUILD_DIR)/$(PROJECT)_pnr.json
	@echo "=== Generating bitstream ==="
	$(GW_PACKAGER) -c $< -o $@

# Full flow
bitstream: $(BUILD_DIR)/$(PROJECT).fs
	@echo "=== Bitstream ready ==="

# Program
.PHONY: prog
prog: $(BUILD_DIR)/$(PROJECT).fs
	@echo "=== Programming device ==="
	$(GW_WRITER) -c $(DEVICE) -f $<

# Clean
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

# Show structure
.PHONY: tree
tree:
	@find . -type f \( -name "*.sv" -o -name "*.v" -o -name "*.sh" -o -name "Makefile" -o -name "*.pcf" -o -name "*.ld" \) | sort | head -50

# Help
.PHONY: help
help:
	@echo "MyRiscV FPGA Softcore Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all       - Build complete bitstream (default)"
	@echo "  sim       - Build for simulation"
	@echo "  bitstream - Generate FPGA bitstream"
	@echo "  prog      - Program the FPGA"
	@echo "  clean     - Remove build artifacts"
	@echo "  tree      - Show project file tree"
