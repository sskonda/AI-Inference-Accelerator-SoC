# Memory Map

All architectural addresses are 32-bit byte addresses. Data words are little-endian.
DMA endpoints must be word aligned, but DMA length can be any byte count and partial
final words use byte enables. Accelerator element addresses must satisfy the
element-width alignment rule.

| Region | Base | End | Size | Owner |
| --- | ---: | ---: | ---: | --- |
| MMIO control | `0x00000000` | `0x00000FFF` | 4 KiB | Register block |
| Scratchpad | `0x10000000` | `0x1000FFFF` | 64 KiB | On-chip SRAM model |
| External memory | `0x80000000` | `0x800FFFFF` | 1 MiB | C++ or UVM memory model |

Addresses outside these regions are illegal. MMIO is reachable only through AXI-Lite;
the DMA and accelerators cannot use the MMIO region as a data endpoint.

## Scratchpad Layout

The scratchpad is a shared byte-addressed region. Hardware does not impose a static
partition. The cooperative scheduler allocates one private 4 KiB slot per task.

Within each task slot, the default software layout is:

| Slot-relative offset range | Size | Purpose |
| --- | ---: | --- |
| `0x000` to `0x3FF` | 1 KiB | Source 0 |
| `0x400` to `0x7FF` | 1 KiB | Source 1 |
| `0x800` to `0xFFF` | 2 KiB | Destination |

The 64 KiB baseline scratchpad therefore supports 16 task slots. These partitions are a
software convention, not separate hardware banks. The bounded accelerator dimensions fit
within each subregion. Banking is evaluated only during the optimization phase.

## External Memory Model

The external memory model is byte-addressable and deterministically initialized by each
test. It supports configurable request acceptance delay, response latency, and write
backpressure. Illegal accesses return an error response and do not modify memory.

The baseline memory interface permits one request in flight. Later performance
experiments may increase outstanding depth without changing the architectural address
map. Each request carries `req_last` to identify the end of a logical DMA burst.

## Data Formats

Vector and reduction elements are signed little-endian integers with a parameterized
element width. The default is 16 bits. Matrix inputs use the same default; accumulators
use a wider signed type before the configured output conversion is applied.

Command descriptors are transferred through MMIO staging registers rather than stored
in external memory in the baseline architecture.
