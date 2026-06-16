# Verification Plan

## Objectives

Verification demonstrates measurable closure for bus behavior, data movement, command
conservation, arithmetic correctness, interrupts, reset, error handling, firmware
interaction, and architectural counters. Passing tests alone are insufficient: assertions
and functional coverage must also show that the planned behavior occurred.

## Layers

| Layer | Purpose |
| --- | --- |
| Verible | Format, parse, and lint all SystemVerilog sources |
| Verilator lint | Check the complete synthesizable hierarchy |
| Primitive tests | Isolate FIFO, skid buffer, RAM, and handshake corner cases |
| C++ harness | Run fast module and SoC scenarios through cycle-accurate interfaces |
| Golden models | Compute independent expected DMA and accelerator results |
| UVM | Drive constrained-random protocols, inject stalls, and collect coverage |
| Assertions | Continuously enforce temporal and structural invariants |
| Performance tests | Check counters and produce repeatable architecture metrics |

## Testbench Architecture

The UVM environment contains active AXI-Lite and memory agents, a virtual sequencer,
passive command and interrupt monitors, a memory mirror, a reference-model adapter, a
scoreboard, and coverage collectors. Drivers use clocking blocks. Monitors sample only
completed handshakes and publish immutable transaction objects.

The scoreboard tracks accepted command IDs and opcodes, expected external-memory writes,
expected interrupt assertions, and accelerator outputs. It reports dropped or duplicated
descriptors, unexpected or duplicate writes, unexpected or missing interrupt assertions,
completion identity errors, and arithmetic mismatches.

## UVM Tests

| Test | Primary purpose |
| --- | --- |
| `smoke_test` | Reset, identity read, one transfer, one command, one interrupt |
| `register_test` | Legal, illegal, read-only, write-one-to-clear, and self-clear behavior |
| `dma_directed_test` | Boundary lengths, alignment policy, overlap rejection, errors, and back-to-back copies |
| `dma_random_test` | Random lengths, addresses, latency, and backpressure |
| `vector_directed_test` | Every vector opcode and arithmetic boundary |
| `vector_random_test` | Random data, lengths, and output stalls |
| `reduction_directed_test` | Length and signed-value corner cases |
| `reduction_random_test` | Random vectors and operation selection |
| `gemm_directed_test` | Dimension, identity, zero, and numeric-boundary cases |
| `gemm_random_test` | Random legal small matrices and invalid dimensions |
| `command_queue_random_test` | Full, empty, occupancy, ordering, and policy behavior |
| `irq_test` | Enable, pending, clear, simultaneous source, and persistence behavior |
| `reset_test` | Reset during idle and every supported busy state |
| `backpressure_test` | Independent bus, memory, and accelerator stalls |
| `mixed_workload_test` | Priorities, shared resources, and interrupt-driven completion |
| `error_injection_test` | Illegal addresses, opcodes, dimensions, and accesses |
| `performance_counter_test` | Event-to-counter correspondence and coherent reads |

The non-UVM command suite exercises every legal opcode, both policies, every
occupancy level, full and empty transitions, starvation override, executor stalls,
invalid opcode handling, reset with queued work, response backpressure, and seeded random
tag/error propagation. The UVM command-queue test independently fills the disabled queue,
checks full and rejected-submission behavior, enables scheduling, and requires every
accepted command ID to retire exactly once.

The non-UVM vector suite implements the directed and randomized vector test intent. It
checks all five vector opcodes against the independent C++ arithmetic model, including
signed and unsigned modes, truncation, saturation, scalar loading, negative values,
odd and maximum lengths, partial write strobes, memory latency, request backpressure,
response backpressure, illegal descriptors, memory errors, and reset during execution.

The non-UVM reduction suite compares sum and maximum against the C++ model. It covers
length one, odd length, power-of-two length, maximum length, signed negative values,
unsigned values, truncating and saturating sums, partial result writes, request and
response stalls, response backpressure, read and write errors, illegal descriptors,
reset during operation, and seeded random data and lengths.

The non-UVM GEMM suite compares every output element against an independent C++ model.
It covers 1-by-1, square, rectangular, inner-dimension-one, zero, identity-like, partial
tile, and maximum-dimension matrices; signed and unsigned arithmetic; truncation and
saturation; memory and response stalls; address and dimension errors; output overlap;
read and write errors; reset during operation; and seeded random matrices. It also
checks exact tiled source-read counts, output writes, byte strobes, final-write marking,
and preservation of rounded-storage padding.

The non-UVM SoC suite drives only AXI-Lite and external-memory top-level signals. It
checks reset, identity and illegal MMIO, direct and queued DMA, vector, reduction, GEMM,
DMA and accelerator interrupts, timer interrupt, queue high-water observation, command
completion counts, DMA byte counts, and total cycles. Every workload moves inputs into
scratchpad and results back out through DMA. External-memory request stalls and response
latency vary across the standard four seeds. The regression runner retains every
block-level suite in addition to the SoC suite.

The host firmware suite uses a deterministic MMIO model to check driver register
programming, task priority, blocked states, interrupt wakeups, completion order, and all
public workload-submission APIs. The SoC suite links those same firmware sources and runs
DMA, vector add, ReLU, clamp, sum, maximum, and matrix tasks together. It verifies private
scratch-slot behavior, highest-priority initial dispatch, complete task retirement,
software scheduling-stall accounting, architectural performance readback, and every
external-memory result against a golden model.

## UVM Implementation

The class-based environment is compiled from `uvm/files.f` with `tb_top` as its top-level
module. The active AXI-Lite agent drives the implemented five-channel single-beat subset
through clocking blocks. The active memory agent owns a byte-addressable model and injects
configurable request backpressure, response latency, and response errors. Passive
interrupt and command agents report external IRQ transitions and tagged command
retirements.

Virtual sequences preload external memory, issue MMIO operations, submit descriptors, and
declare expected destination bytes through the scoreboard API. The scoreboard compares
external-memory writes, associates every successful command submission with a completion
ID and opcode, rejects unexpected or duplicate completions, and requires queue drain when
requested by a test. Coverage subscribers sample register direction and offset, DMA
lengths, opcode and priority, queue occupancy and policy, memory delay and error behavior,
interrupt levels, and architectural errors.

The regression manifest contains all 17 tests shown above. Run:

```sh
make uvm-check
make uvm-compile
make uvm-smoke UVM_TEST=smoke_test UVM_SEED=1
make uvm-regress UVM_SEEDS="1 7 19 41"
```

`make uvm-check` is simulator independent. The compile, smoke, and regression targets
require `vlib`, `vlog`, `vsim`, and a UVM source tree. Set `UVM_HOME` to the directory
containing `uvm_pkg.sv` and `uvm_macros.svh` when the simulator installation does not
expose that location through `QUESTA_HOME` or `MTI_HOME`.

## Assertions

Assertions cover stable payload while stalled, no unknown control after reset, legal FSM
states, FIFO and command queue bounds, exact DMA byte limits, DMA start rejection before
traffic, scratchpad bounds, no early completion, command conservation, sticky interrupts,
disabled interrupt masking, legal register writes, and coherent performance snapshots.

Complex end-to-end ordering is checked with reference queues in monitors and scoreboards
instead of opaque temporal properties.

## Functional Coverage

Coverage includes all register offsets and access types, opcodes, vector and reduction
operations, matrix dimension classes, DMA length classes, backpressure duration, queue
occupancy and transitions, scheduler policies, priority combinations, interrupt
enable/pending/clear combinations, error codes, and reset during idle or busy operation.
Crosses focus on interactions likely to hide defects rather than exhaustive Cartesian
products.

## Seeds and Reproducibility

Every randomized test logs its seed. The default regression seeds are `1`, `7`, `19`,
and `41`. Failures print a replay command. External memory initialization and latency
sequences derive only from the selected seed.

## Closure Criteria

- Every available public check passes.
- Every planned test supported by the installed simulator passes.
- No assertion failure is present in regression logs.
- Functional coverage goals are met or each unreachable bin has a technical explanation.
- No mismatch, dropped command, duplicate completion, or unintended memory write remains.
- Missing commercial-simulator results are reported as not run, never as passed.
