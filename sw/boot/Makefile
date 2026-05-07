# Makefile for MyRiscV Boot Software
#

RISCV_PREFIX = riscv64-unknown-elf-
CC = $(RISCV_PREFIX)gcc
OBJCOPY = $(RISCV_PREFIX)objcopy
OBJDUMP = $(RISCV_PREFIX)objdump
SIZE = $(RISCV_PREFIX)size

# Target
TARGET = boot

# Directories
BUILD_DIR = build
LINKER_DIR = ../linker
TOOLS_DIR = ../../tools

# Source files
SRC = boot.c startup.S

# Linker script
LDSCRIPT = $(LINKER_DIR)/iram.ld

# RV32I with no compressed instructions
MARCH = rv32i
MABI = ilp32

# Compiler flags
CFLAGS = -march=$(MARCH) -mabi=$(MABI) -nostdlib -ffreestanding -O2
CFLAGS += -Wall -Wextra
ASMFLAGS = -march=$(MARCH) -mabi=$(MABI)

# Linker flags
LDFLAGS = -nostdlib -nodefaultlibs -T $(LDSCRIPT)

# Output files
ELF = $(BUILD_DIR)/$(TARGET).elf
BIN = $(BUILD_DIR)/$(TARGET).bin
HEX = $(BUILD_DIR)/$(TARGET).hex
DUMP = $(BUILD_DIR)/$(TARGET).dump
MAP = $(BUILD_DIR)/$(TARGET).map
INIT_HEX = $(BUILD_DIR)/iram_init.hex

.PHONY: all clean run sync

all: $(BIN) $(INIT_HEX) sync

sync: $(INIT_HEX)
	cp $(INIT_HEX) ../../rtl/iram_init.hex
	@echo "Synced to RTL directory"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(ELF): $(SRC) $(LDSCRIPT) | $(BUILD_DIR)
	$(CC) $(ASMFLAGS) $(SRC) -o $@ $(LDFLAGS)
	@echo "=== Build complete ==="
	$(SIZE) $@

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@
	@ls -lh $@

$(HEX): $(BIN)
	xxd -p $< | tr -d '\n' > $@
	@echo "Generated hex file"

$(DUMP): $(ELF)
	$(OBJDUMP) -d $< > $@
	@echo "=== Disassembly ==="
	@head -50 $@

$(INIT_HEX): $(BIN)
	python3 $(TOOLS_DIR)/bin2mif.py $< $@
	@echo "Generated Verilog initialization"

run: $(ELF)
	$(OBJDUMP) -d $< | less

clean:
	rm -rf $(BUILD_DIR)

# Show memory usage
info: $(ELF)
	$(SIZE) -A -d $< | grep -E '(iram|text|data|bss|stack)'
