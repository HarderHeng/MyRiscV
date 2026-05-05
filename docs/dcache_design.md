# D-Cache Design Document

## Overview

The D-Cache (Data Cache) is a 2KB direct-mapped write-back cache designed to reduce data access latency and improve performance by caching frequently accessed data from DRAM.

## Specifications

| Parameter | Value | Description |
|-----------|-------|-------------|
| Size | 2KB | Total cache capacity |
| Structure | Direct-mapped | 1-way set associative |
| Line size | 16B | 4 words per line |
| Number of lines | 128 | 2KB / 16B |
| Index bits | 7 | addr[8:2] selects line |
| Tag size | 8 bits | addr[31:24] (upper 8 bits) |
| Write policy | Write-back | Modified data held in cache |
| Allocation policy | Write-allocate | Miss brings line into cache |

## Cache Line Format

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Valid (1) │ Dirty (1) │ Tag (8) │ Word 0-3 (128 bits)                  │
└─────────────────────────────────────────────────────────────────────────┘
```

Each cache line stores:
- 1 valid bit
- 1 dirty bit (indicates modified data not written to memory)
- 8 tag bits (upper address bits)
- 4 words of data (128 bits)

## Address Mapping

Same as I-Cache:
- `addr[31:24]` = Tag (8 bits)
- `addr[8:2]` = Line index (7 bits → 128 lines)
- `addr[3:2]` = Word offset within line (2 bits → 4 words)
- `addr[1:0]` = Byte offset within word (for byte/half-word accesses)

## State Machine

The D-Cache controller has the following states:

| State | Description |
|-------|-------------|
| IDLE | Waiting for data access request |
| READ_HIT | Read hit, returning data |
| WRITE_HIT | Write hit, updating cache line and setting dirty |
| READ_MISS | Read miss, need to fill |
| WRITE_MISS | Write miss, need to fill then update |
| FILL | Loading data from memory |
| EVICT | Evicting dirty line before fill |
| EVICT_WRITE | Writing dirty line to memory |

### State Transitions

```
                         ┌──────────────────────────────────────────────┐
                         │                                              │
                         ▼                                              │
       ┌─────┐    read     ┌───────────┐                               │
       │ IDLE├───────────►│ READ_HIT  │◄──────────────────────────────┤
       └──┬──┘            └─────┬─────┘                               │
          │    write             │                                     │
          │                     ▼                                     │
          │               ┌────────────┐                              │
          ├──────────────►│ WRITE_HIT  │                              │
          │               └──────┬─────┘                              │
          │                      │                                     │
          │    miss + dirty      │                                     │
          │                      ▼                                     │
          │               ┌───────────┐    clean     ┌─────────────┐  │
          │◄──────────────│   EVICT   │◄────────────►│  READ_MISS  │  │
          │               └───┬───────┘              └──────┬──────┘  │
          │                   │                              │        │
          │ dirty              │ fill done                   │ fill   │
          │                   │                             │ done   │
          │                   ▼                             ▼        │
          │            ┌─────────────┐             ┌───────────┐    │
          │            │EVICT_WRITE │             │  FILL     │─────┘
          │            └──────┬──────┘             └───────────┘
          │                   │                        │
          │                   │ writeback                │
          │                   │ complete                │
          │                   ▼                        ▼
          │◄──────────────────────────────────────────────────────┘
```

## Write-Back Operation

When a dirty cache line is being evicted:

1. Detect dirty bit is set
2. Transition to EVICT state
3. Write entire cache line (4 words) to memory
4. Wait for memory write to complete (EVICT_WRITE)
5. Then proceed with the fill for the new data

## Dirty Bit Management

The dirty bit is set when:
- A write hit occurs (WRITE_HIT state)
- The cache line is modified in the cache

The dirty bit is cleared when:
- The line is successfully written back to memory (EVICT_WRITE state)
- On cache initialization (reset)

## BSRAM Usage

The D-Cache uses 1 SDPB block (18Kbit) for storage:
- Tag array: 128 × 10 bits (valid + dirty + 8-bit tag)
- Data array: 128 × 128 bits (4 words per line)

Total storage required: 128 × (1 + 1 + 8 + 128) = 128 × 138 = 17,664 bits ≈ 2.2KB

This is slightly more than I-Cache due to the dirty bit, but still fits in one SDPB.

## Write Buffer

To improve write performance, a small write buffer could be added to hold dirty data during write-back while the CPU continues. This is not implemented in the current version to save resources.

## Performance Impact

With a 2KB direct-mapped write-back cache:
- Write hit: 1 cycle (update cache, set dirty)
- Write miss (write-allocate): ~4-5 cycles (fill + update + set dirty)
- Read hit: 1 cycle
- Read miss: ~3 cycles (fill from memory)
- Eviction of dirty line: +2 cycles (write-back)

## Cache Coherency

This is a single-core design, so no cache coherency issues arise. If a Debug Module or DMA accesses memory directly, they should invalidate or flush the cache as needed.

## Integration

The D-Cache sits between the CPU data access port and the AHB-Lite bus:

```
     CPU MEM                   AHB-Lite Bus
        │                          │
        ▼                          ▼
   ┌─────────┐                ┌─────────┐
   │ D-Cache │◄──────────────►│   Bus   │
   └─────────┘                └─────────┘
        │                          │
        ▼                          ▼
   (hit data)              DRAM/Flash/Peripherals
```

## Bypass Regions

The following address regions bypass the D-Cache (uncached):

| Region | Range | Reason |
|--------|-------|--------|
| Peripherals | 0x1000_xxxx | I/O registers must be accessed precisely |
| Flash | 0x2000_xxxx | Direct memory-mapped I/O |

Only IRAM and DRAM regions (0x8000_xxxx) are cached.

## Implementation

The D-Cache is implemented in `rtl/soc/ahblite_dcache.sv`.
