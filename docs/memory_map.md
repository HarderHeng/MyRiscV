# MyRiscV Memory Map

## Overview

This document describes the memory architecture for the MyRiscV RISC-V softcore implemented on Tang Nano 9K (GW1NR-9C) FPGA.

## Memory Map Summary

```
Address Range              Size     Type      Description
===============================================================================
0x0000_0000 - 0x0FFF_FFFF  256MB   Reserved  Reserved address space

0x1000_0000 - 0x1000_FFFF   64KB    I/O       Peripheral space
  0x1000_0000 - 0x1000_001F           UART0    UART registers
  0x1000_0100 - 0x1000_01FF           GPIO     GPIO registers
  0x1000_0200 - 0x1000_02FF           CLINT    Core local interrupt timer

0x2000_0000 - 0x2012_FFFF   76KB     ROM       On-chip Flash (FLASH608K)
  0x2000_0000                         Reset vector (CPU starts here)
  0x2000_1000                         User program area

0x8000_0000 - 0x8000_FFFF   64KB     SRAM      On-chip SRAM (BSRAM)
  0x8000_0000 - 0x8000_3FFF  16KB              IRAM (Instruction)
  0x8000_4000 - 0x8000_5FFF   8KB              DRAM (Data)
  0x8000_6000 - 0x8000_7FFF   8KB              Reserved
```

## Detailed Description

### Peripheral Space (0x1000_xxxx)

Base address: 0x1000_0000

#### UART0 (0x1000_0000 - 0x1000_001F)

| Offset | Name   | Access | Description |
|--------|--------|--------|-------------|
| 0x00 | TXDATA | WO | Transmit data register (lower 8 bits) |
| 0x04 | RXDATA | RO | Receive data register (bits [7:0], bit [31] = valid) |
| 0x08 | STATUS | RO | Status register (bit [0] = TX busy, bit [1] = RX has data) |
| 0x0C | DIVISOR | RW | Baud rate divisor (default 234 for 115200 @ 27MHz) |

#### GPIO (0x1000_0100 - 0x1000_01FF)

| Offset | Name   | Access | Description |
|--------|--------|--------|-------------|
| 0x00 | DATA | RW | GPIO data register |
| 0x04 | DIR | RW | GPIO direction (1=output, 0=input) |

#### CLINT (0x1000_0200 - 0x1000_02FF)

| Offset | Name   | Access | Description |
|--------|--------|--------|-------------|
| 0x00 | MSIP | RW | Machine Software Interrupt Pending |
| 0x04 | MTIMECMP | RW | Machine Timer Compare |
| 0x08 | MTIME | RO | Machine Timer (lower 32 bits) |
| 0x0C | MTIME + 4 | RO | Machine Timer (upper 32 bits) |

### Flash Space (0x2000_xxxx)

Base address: 0x2000_0000

The on-chip Flash is organized as 32K × 32-bit words (128KB total, 76KB user area).

**Important:** Flash accesses have a 2-cycle latency.

Address mapping within Flash:
- `addr[16:2]` = word address (maximum 32K words)
- `addr[16:9]` = page address (XADR)
- `addr[5:0]` = word offset within page (YADR)

Flash is accessed via XIP (Execute In Place) - the CPU can directly execute code from Flash without copying to RAM first.

### SRAM Space (0x8000_xxxx)

Base address: 0x8000_0000

#### IRAM (0x8000_0000 - 0x8000_3FFF)

- Size: 16KB (4096 × 32-bit words)
- Word index: `addr[13:2]`
- Implementation: 8 × Gowin SDPB primitives
- Access: Synchronous read/write
- Cacheable: Yes

#### DRAM (0x8000_4000 - 0x8000_5FFF)

- Size: 8KB (2048 × 32-bit words)
- Word index: `addr[12:2]`
- Implementation: 4 × Gowin SDPB primitives
- Access: Synchronous read/write
- Cacheable: Yes

## Cacheability

| Region | Cacheable | Reason |
|--------|-----------|--------|
| Peripherals (0x1000_xxxx) | No | I/O registers must be accessed precisely |
| Flash (0x2000_xxxx) | No | XIP - code executes directly from Flash |
| IRAM (0x8000_0000) | Yes | Main instruction memory |
| DRAM (0x8000_4000) | Yes | Main data memory |

## BSRAM Resource Usage

| Component | SDPB Blocks | Size | Notes |
|-----------|-------------|------|-------|
| IRAM | 8 | 16KB | 8 × 512 × 32-bit |
| DRAM | 4 | 8KB | 4 × 512 × 32-bit |
| RegFile | 3 | 32×32bit | 3 × 512 × 32-bit |
| I-Cache (optional) | 1 | 2KB | Direct-mapped |
| D-Cache (optional) | 1 | 2KB | Direct-mapped, write-back |
| **Total** | **16-18** | **~30KB** | **of 26 BSRAM blocks** |

## Boot Sequence

1. CPU reset vector at 0x2000_0000 (Flash)
2. CPU fetches first instruction from Flash
3. Software copies code/data to IRAM/DRAM as needed
4. Execution continues from IRAM or Flash depending on program

## Design Notes

- Flash uses 2-cycle read latency (handled by CPU wait state logic)
- IRAM and DRAM use 1-cycle latency
- All memories are 32-bit word-aligned
- Byte enable (HSTRB/BE) signals support byte, half-word, and word accesses
