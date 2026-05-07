# MyRiscV - RISC-V 5-Stage Pipeline FPGA Softcore

A complete RISC-V RV32I processor implementation for TangNano-9K (Gowin GW1NR-9C FPGA).

## Features

- **5-Stage Pipeline**: IF-ID-EX-MEM-WB
- **RV32I Instruction Set**: All integer instructions
- **AHB-Lite Bus**: Separate I/D bus architecture
- **Peripherals**: UART (115200 baud)
- **Target**: TangNano-9K (27MHz)

## Quick Start

### 1. Compile Software

```bash
cd sw/boot
make clean
make
```

This generates:
- `build/boot.bin` - Raw binary
- `build/boot.elf` - ELF with symbols
- `build/iram_init.v` - Verilog initialization for IRAM

### 2. Build Bitstream

```bash
make bitstream
```

### 3. Program FPGA

```bash
make prog
```

## Project Structure

```
uart/
├── rtl/
│   ├── core/               # CPU pipeline
│   │   ├── cpu_core.sv    # Top integration
│   │   ├── if_stage.sv    # Instruction fetch
│   │   ├── id_stage.sv    # Decode
│   │   ├── ex_stage.sv    # Execute
│   │   ├── mem_stage.sv   # Memory
│   │   ├── wb_stage.sv    # Writeback
│   │   ├── regfile.sv     # Register file
│   │   ├── hazard_unit.sv  # Hazard detection
│   │   └── forward_unit.sv # Forwarding
│   ├── soc/
│   │   ├── myriscv_soc_top.sv
│   │   ├── ahblite_bus.sv
│   │   ├── ram/
│   │   │   ├── iram.sv    # 16KB instruction RAM
│   │   │   ├── dram.sv    # 8KB data RAM
│   │   │   └── flash_ctrl.sv
│   │   └── perips/
│   │       └── uart.sv
├── sw/
│   ├── boot/               # Boot software
│   │   ├── boot.c         # Hello World program
│   │   ├── startup.S      # Startup code
│   │   └── Makefile
│   └── linker/
│       └── iram.ld        # Linker script
├── constraints/
│   └── myriscv.pcf        # Pin constraints
└── tools/
    └── bin2mif.py         # Binary to Verilog converter
```

## Address Map

| Address | Size | Device |
|---------|------|--------|
| 0x1000_0000 | 4B | UART TXDATA |
| 0x1000_0008 | 4B | UART STATUS |
| 0x8000_0000 | 16KB | IRAM (code) |
| 0x8000_4000 | 8KB | DRAM (stack) |

## CPU Architecture

### Pipeline Stages

1. **IF** - Instruction Fetch from IRAM
2. **ID** - Decode + Register Read
3. **EX** - ALU + Branch Compare
4. **MEM** - Load/Store
5. **WB** - Register Writeback

### Hazard Handling

- Load-Use: 1-cycle stall
- Data Forwarding: EX/MEM → ID/EX
- Branch: Flush on mispredict

## Software Development

### Hello World Program

The boot program (`sw/boot/boot.c`) prints "Hello, World!\n" every ~5 seconds via UART.

### Modifying the Program

1. Edit `sw/boot/boot.c`
2. Run `make` in `sw/boot/`
3. Rebuild bitstream: `make bitstream`

### UART Output

- Baud: 115200
- 8N1 format
- Connect to TangNano-9K USB-UART
