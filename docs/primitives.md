# Storage and Flow-Control Primitives

## Synchronous FIFO

`sync_fifo` is a single-clock FIFO with valid/ready input and output channels. Storage is
an unreset unpacked array. Read and write pointers plus occupancy reset synchronously when
`rst_n` is low.

The current head is presented combinationally when the FIFO is nonempty. Enqueue and
dequeue state changes occur on the rising edge. A full FIFO accepts a push when a pop is
accepted in the same cycle, preserving one transfer per cycle without changing occupancy.
An empty FIFO does not bypass a new push directly to the output; the new item becomes
visible after the rising edge.

Pointer wrap is explicit, so depth one, power-of-two depths, and non-power-of-two depths
use the same implementation. Occupancy ranges from zero through `DEPTH`.

## Skid Buffer

`skid_buffer` is a one-entry elastic buffer. With no stall it provides a combinational
input-to-output path and adds no cycle of latency. When the downstream interface stalls,
the accepted input is retained in an unreset datapath register guarded by a resettable
valid bit.

If a buffered item is released while a new input is accepted, the new item replaces it
on the same rising edge. Output valid and data remain stable for the full duration of a
stall.

## Simple Dual-Port RAM

`simple_dual_port_ram` has one synchronous read port and one byte-enabled write port. The
base read latency is one cycle. Setting `REGISTER_OUTPUT` adds a second output-register
cycle.

Read-during-write to the same address is read-first: the read returns the old word and the
new word is visible to later reads. Byte lanes with a clear write strobe retain their old
contents.

Reset clears read-valid pipeline state only. It does not clear memory or read-data
registers. Tests must initialize locations before reading them. `INIT_FILE`, `load_hex`,
and `fill_memory` provide deterministic simulation initialization without adding a reset
network to the storage array.

## Scratchpad Wrapper

`scratchpad_ram` converts aligned architectural byte addresses into RAM word indexes.
Legal accesses must:

- Start at or above `BASE_ADDR`.
- Fit completely inside `SIZE_BYTES`.
- Align to the configured data-word size.

Illegal reads and writes assert their error output and are blocked before reaching RAM.
The baseline wrapper supports one read and one write each cycle and inherits the RAM's
read-first collision behavior.

## Verification

The primitive Verilator executable checks:

- FIFO reset, empty, full, ordering, overflow backpressure, underflow protection, and
  simultaneous push/pop.
- FIFO depths one, three, and four.
- Skid-buffer bypass, capture, hold, release, and same-cycle replacement.
- RAM full and partial writes, one- and two-cycle read latency, read-first collisions, and
  memory persistence across reset.
- Scratchpad legal access, out-of-bounds rejection, and alignment rejection.
- Random FIFO operation against a C++ queue and random RAM writes against a byte-strobe
  reference model.
