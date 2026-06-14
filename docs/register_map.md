# Register Map

The control interface uses 32-bit little-endian words and byte addresses. Register
accesses must be word aligned. Unsupported addresses return a slave error on reads or
writes and set `ERROR_STATUS.ILLEGAL_MMIO`. Writes to read-only registers also return a
slave error.

## AXI-Lite Subset

The register block implements the five independent AXI-Lite channels for single-beat
transactions. Write address and write data can arrive in either order. The block accepts
one write and one read transaction at a time, has no transaction IDs, and does not
support bursts. Once asserted, response valid and payload remain stable until the manager
asserts ready. Byte strobes update only selected bytes. Software must issue word-aligned
addresses; unaligned offsets are unsupported and return a slave error.

| Offset | Name | Access | Reset | Description |
| ---: | --- | --- | ---: | --- |
| `0x000` | `SOC_ID` | RO | `0x534F4301` | Implementation identity |
| `0x004` | `VERSION` | RO | `0x00010000` | Major, minor, and patch version |
| `0x008` | `CTRL` | RW/P | `0x00000000` | Global enable, counter clear, scheduler policy |
| `0x00C` | `STATUS` | RO | `0x00000001` | Ready, busy, and error summary |
| `0x010` | `IRQ_STATUS` | RO/W1C | `0x00000000` | Sticky interrupt pending bits |
| `0x014` | `IRQ_ENABLE` | RW | `0x00000000` | Interrupt source enables |
| `0x018` | `TIMER_CTRL` | RW | `0x00000000` | Timer enable, periodic mode, and interval |
| `0x01C` | `TIMER_VALUE` | RO | `0x00000000` | Current timer count |
| `0x020` | `DMA_SRC_ADDR` | RW | `0x00000000` | DMA source byte address |
| `0x024` | `DMA_DST_ADDR` | RW | `0x00000000` | DMA destination byte address |
| `0x028` | `DMA_LEN_BYTES` | RW | `0x00000000` | Exact DMA transfer length |
| `0x02C` | `DMA_CTRL` | RW/P | `0x00000000` | Start and completion-interrupt enable |
| `0x030` | `DMA_STATUS` | RO/W1C | `0x00000000` | Busy, done, and error status |
| `0x034` | `CMD_OPCODE` | RW | `0x00000000` | Staged accelerator opcode |
| `0x038` | `CMD_SRC0_ADDR` | RW | `0x00000000` | First scratchpad source byte address |
| `0x03C` | `CMD_SRC1_ADDR` | RW | `0x00000000` | Second scratchpad source byte address |
| `0x040` | `CMD_DST_ADDR` | RW | `0x00000000` | Scratchpad destination byte address |
| `0x044` | `CMD_LEN` | RW | `0x00000000` | Vector or reduction element count |
| `0x048` | `CMD_M` | RW | `0x00000000` | Matrix row count |
| `0x04C` | `CMD_N` | RW | `0x00000000` | Matrix column count |
| `0x050` | `CMD_K` | RW | `0x00000000` | Matrix inner dimension |
| `0x054` | `CMD_FLAGS` | RW | `0x00000000` | Signedness, saturation, and operation flags |
| `0x058` | `CMD_PRIORITY` | RW | `0x00000000` | Staged command priority |
| `0x05C` | `CMD_SUBMIT` | WO/P | `0x00000000` | Atomically enqueue staged descriptor |
| `0x060` | `CMD_STATUS` | RO/W1C | `0x00000000` | Queue, completion, and command error state |
| `0x064` | `PERF_SELECT` | RW | `0x00000000` | Performance counter selector |
| `0x068` | `PERF_VALUE` | RO | `0x00000000` | Selected counter low word and snapshot trigger |
| `0x06C` | `PERF_VALUE_HI` | RO | `0x00000000` | Selected counter snapshot high word |
| `0x070` | `ERROR_STATUS` | RO/W1C | `0x00000000` | Sticky global error bits |
| `0x074` | `CMD_ID` | RW | `0x00000000` | Firmware-provided command identifier |
| `0x078` | `SCHED_CTRL` | RW | `0x00000000` | Policy and starvation threshold |
| `0x07C` | `QUEUE_STATUS` | RO | `0x00000000` | Occupancy, full, empty, and high-water mark |

Access codes:

- `RO`: read-only.
- `RW`: read and write.
- `WO`: write-only.
- `W1C`: writing one clears the corresponding sticky bit.
- `P`: one-cycle pulse; the written action bit reads as zero.

## Control Bits

`CTRL` bit 0 enables command execution. Bit 1 clears all performance counters for one
cycle. Bit 2 selects priority-first scheduling when set and round-robin scheduling when
clear.

`DMA_CTRL` bit 0 starts a transfer. Bit 1 enables the DMA completion interrupt source.
A start write while busy is rejected and records `DMA_BUSY`.

`CMD_SUBMIT` bit 0 commits the staged descriptor. Submission while either queue-full
indication is asserted, or while an earlier staged command is pending acceptance, is
rejected without changing queue contents.

`DMA_STATUS` bits 1 and 2 and `CMD_STATUS` bits 0 and 1 are sticky. Writing one clears
the corresponding status bit. New hardware status wins over a simultaneous clear.

`ERROR_STATUS` uses error-code values as bit indexes. Writing one clears an error bit;
new errors win over a simultaneous clear.

## Interrupt Bits

| Bit | Source |
| ---: | --- |
| 0 | DMA complete |
| 1 | Command complete |
| 2 | Accelerator complete |
| 3 | Error |
| 4 | Timer tick |

## Coherent Counter Read

Reading `PERF_VALUE` captures the selected 64-bit counter into a snapshot register and
returns its low word. A following read of `PERF_VALUE_HI` returns the corresponding high
word even if the live counter increments between reads.
