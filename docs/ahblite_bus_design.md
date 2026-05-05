# AHB-Lite Bus Design Document

## Overview

The AHB-Lite Bus is a simplified AMBA AHB-Lite compatible bus matrix designed for the MyRiscV softcore on Tang Nano 9K FPGA.

## Features

- Single master (CPU), multiple slaves
- Address-decoded slave selection
- Combinational address decoding
- Single-cycle latency (no wait states for memory)
- No burst support (SINGLE transfers only)

## Bus Signals

### Master Interface (CPU side)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| HADDR | 32 | Master→Bus | Address |
| HWDATA | 32 | Master→Bus | Write data |
| HRDATA | 32 | Bus→Master | Read data |
| HWRITE | 1 | Master→Bus | Write enable |
| HSEL | 1 | Bus→Slave | Slave select |
| HREADY | 1 | Master→Bus | Transfer done |
| HREADYOUT | 1 | Slave→Bus | Slave ready |
| HRESP | 1 | Slave→Bus | Response (0=OK) |
| HTRANS | 2 | Master→Bus | Transfer type |
| HSIZE | 3 | Master→Bus | Size (0=8b, 1=16b, 2=32b) |
| HSTRB | 4 | Master→Bus | Byte strobe |

### Transfer Types (HTRANS)

| HTRANS | Type | Description |
|--------|------|-------------|
| 2'b00 | IDLE | No transfer |
| 2'b01 | BUSY | Master busy (not used) |
| 2'b10 | NONSEQ | Start of non-sequential transfer |
| 2'b11 | SEQ | Sequential transfer |

## Address Map

| Address Range | Size | Slave | Description |
|--------------|------|-------|-------------|
| 0x1000_0000 - 0x1000_FFFF | 64KB | Peripherals | UART, GPIO |
| 0x2000_0000 - 0x2012_FFFF | 76KB | Flash | On-chip FLASH608K |
| 0x8000_0000 - 0x8000_3FFF | 16KB | IRAM | Instruction RAM |
| 0x8000_4000 - 0x8000_5FFF | 8KB | DRAM | Data RAM |

## Address Decode Logic

```
is_sram    = (HADDR[31:28] == 4'h8);   // 0x8xxx_xxxx
is_flash   = (HADDR[31:28] == 4'h2);   // 0x2xxx_xxxx
is_periph  = (HADDR[31:28] == 4'h1);   // 0x1xxx_xxxx

is_iram    = is_sram && (HADDR[14] == 1'b0);  // 0x8000_0000 - 0x8000_3FFF
is_dram    = is_sram && (HADDR[14] == 1'b1);  // 0x8000_4000 - 0x8000_5FFF
```

## Slave Connections

| Slave | Selection | Data Width | Latency |
|-------|-----------|------------|---------|
| IRAM | sel_iram | 32-bit | 1 cycle |
| DRAM | sel_dram | 32-bit | 1 cycle |
| Flash | sel_flash | 32-bit | 2 cycles |
| Peripherals | sel_periph | 32-bit | 1 cycle |

## Implementation

The bus is implemented in `rtl/soc/ahblite_bus.sv` using pure combinational logic for address decoding and multiplexed read data return.

```systemverilog
// Example: Read data mux
always @(*) begin
    if (sel_iram)    hrdata = s0_rdata;
    else if (sel_dram) hrdata = s1_rdata;
    else if (sel_flash) hrdata = s2_rdata;
    else if (sel_periph) hrdata = s3_rdata;
    else hrdata = 32'h0;
end
```

## Usage

The AHB-Lite bus is instantiated in `MyRiscV_soc_top.sv` to connect the CPU to all memory and peripheral modules.

```systemverilog
AHB_Lite_Bus u_bus (
    .clk(clk),
    .rst(rst),
    // Master interface from CPU
    .haddr_m(cpu_haddr),
    // ... other signals
    // Slave interfaces to memories
    .s0_* (iram_*),
    .s1_* (dram_*),
    .s2_* (flash_*),
    .s3_* (periph_*)
);
```
