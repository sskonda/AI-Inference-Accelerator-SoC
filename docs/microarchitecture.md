# Microarchitecture

## Design Principles

The implementation favors explicit state machines, named architectural constants,
valid/ready flow control, and narrow ownership boundaries. Large datapath arrays are not
reset; reset clears state, valid bits, visible counters, queue metadata, pending
interrupts, and status only.

Shared definitions live in `rtl/packages`. Interfaces live in `rtl/interfaces` and encode
the stable-payload and no-unknown protocol assertions used by the leaf blocks.

## AXI-Lite Register Block

The register block implements a single-beat five-channel AXI-Lite subset. Write address
and write data are independently accepted and paired internally, so address-first,
data-first, and same-cycle writes are all legal. Read and write responses are held
stable until accepted.

Side effects are explicit:

- `CTRL.PERF_CLEAR`, `DMA_CTRL.START`, and `CMD_SUBMIT.SUBMIT` are self-clearing pulses.
- `IRQ_STATUS`, `DMA_STATUS`, `CMD_STATUS`, and `ERROR_STATUS` use write-one-to-clear
  bits where documented.
- `PERF_VALUE` snapshots the selected 64-bit counter before `PERF_VALUE_HI` is read.
- Illegal offsets and read-only writes return a slave error and set sticky status.

## DMA

The DMA engine is a correctness-first single-word pipeline. It validates the complete
source and destination ranges before memory traffic, issues one aligned source read,
buffers the returned word, issues one destination write, and advances the byte count.
Different-base overlapping ranges are rejected during validation so the baseline does
not expose ambiguous copy ordering.

The final write uses byte enables for exact partial-word completion. Logical burst
boundaries are exposed through `req_last`, but the baseline memory interface permits one
outstanding request. This keeps response ordering simple while preserving a clean path to
later burst and outstanding-depth experiments.

## Scratchpad and Memory Fabric

The scratchpad wrapper maps byte addresses to read-first RAM word indexes. Illegal or
misaligned accesses are blocked before reaching storage.

The SoC memory fabric arbitrates DMA source, DMA destination, vector, reduction, and
matrix initiators. It rotates priority after each accepted request and holds one
registered transaction until the response returns. Requests route either to scratchpad or
to the external-memory simulation port. Unmapped data addresses complete locally with an
error response.

## Command Queue and Scheduler

The command queue stores complete descriptors in shared slots. Reset clears only queue
valid metadata, occupancy, high-water mark, selection lock, and scheduling pointers.
Descriptor payload storage is not reset because invalid slots are never selected.

Two policies are supported:

- Round-robin scans valid slots from the slot after the last pop.
- Priority-first selects highest priority, then greatest age, then lowest slot.

A programmable starvation threshold can override priority-first selection for old
entries. A zero threshold disables the override. The command processor permits one
in-flight descriptor and waits for a tagged response before retiring the command.

## Vector Accelerator

The vector datapath processes packed 16-bit lanes on a 32-bit memory word. It serializes
memory operations through one initiator but performs lane arithmetic in parallel. Add,
multiply, and clamp read two source words. Scale loads a scalar from source 1 before
streaming source 0. ReLU reads only source 0.

Signedness and saturation are descriptor flags. The final partial result word uses byte
strobes so neighboring scratchpad bytes remain unchanged.

## Reduction Accelerator

The reduction datapath applies a balanced lane tree inside each memory word, then folds
one partial result per word into a wide accumulator. Sum uses the configured accumulator
width until final conversion. Maximum returns an existing element. One result word is
written with byte strobes.

The lane tree keeps the default arithmetic path short and scales logarithmically with
wider memory words.

## Matrix Accelerator

The matrix accelerator computes compact row-major integer GEMM in 4-by-4 tiles. For each
inner-dimension step, valid A-row elements and B-column elements are loaded once and
reused across all active outputs in the tile. Accumulators stay wide until final
truncating or saturating conversion.

The baseline uses one memory initiator and writes one output element at a time. Partial
edge tiles suppress inactive rows or columns. Destination overlap with either source is
rejected before memory traffic.

## Timer, Interrupts, and Counters

The timer is configured entirely through visible control fields. One-shot mode disarms
after one tick; periodic mode restarts the counter.

The interrupt controller stores pending sources independently from enable bits. Source
events win over simultaneous clears. Interrupt latency is measured from external
assertion to service and is reported to the performance counters.

Performance counters are 64-bit saturating counters. Event counters increment or add
exact byte counts. High-water counters retain maxima.

## Timing and Efficiency Considerations

The current implementation intentionally limits concurrency:

- One DMA word is buffered.
- One memory request is outstanding in the fabric.
- One queued command is in flight.
- Each accelerator owns one scratchpad initiator.

This keeps ordering, scoreboarding, and firmware completion semantics clear for the
baseline. Tunable parameters already expose FIFO depth, DMA logical burst length,
command queue depth, starvation threshold, vector/reduction length limits, and matrix
tile and dimension limits for the optimization phase.
