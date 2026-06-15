# Performance Analysis

## Measurement Model

The SoC exposes architectural counters for:

- total cycles;
- DMA active and stalled cycles;
- accelerator active and stalled cycles;
- command queue high-water mark;
- completed commands;
- exact DMA bytes read and written;
- maximum interrupt service latency;
- hardware scheduler stalls.

The C++ firmware driver reads counters through the coherent `PERF_VALUE` and
`PERF_VALUE_HI` snapshot protocol. The SoC regression checks that cycle, byte,
completion, and queue counters become nonzero during mixed workloads.

## Current Baseline Status

Milestone 16 documents the measurement surface before the baseline data capture. The
repeatable performance run and committed CSV or JSON tables are scheduled for milestone
17. No baseline performance number is claimed in this document until produced by a
checked script.

Current measured verification-adjacent data from milestone 15:

| Metric | Value |
| --- | ---: |
| Verilator coverage databases | 44 |
| Unique coverage points | 31,280 |
| Covered coverage points | 20,856 |
| Point coverage | 66.68% |

These are coverage metrics, not throughput metrics.

## Expected Baseline Measurements

Milestone 17 will record the following workloads in machine-readable form under
`perf/results/`:

| Workload | Primary metrics |
| --- | --- |
| DMA copy | cycles, active cycles, stalled cycles, bytes read, bytes written |
| Vector add | command cycles, accelerator active cycles, memory stalls |
| Vector ReLU or clamp | command cycles, byte strobes, accelerator utilization |
| Reduction sum | command cycles, active cycles, stalled cycles |
| Reduction maximum | command cycles, active cycles, stalled cycles |
| Matrix multiply | command cycles, output count, memory stalls |
| Mixed firmware workload | total cycles, queue high-water, interrupt latency, completion count |

## Optimized Metrics

No optimized metric is claimed before the optimization phase. Milestone 18 will compare
accepted and rejected configurations against the milestone 17 baseline using the same
workloads, seeds, and counter definitions.

## Known Performance Bottlenecks

The expected baseline bottlenecks are visible from the RTL structure:

- The memory fabric allows one outstanding request.
- The DMA engine buffers one word and waits for each write response before the next read.
- The command processor allows one queued accelerator command in flight.
- The vector accelerator serializes source reads and destination writes.
- The reduction accelerator folds memory words through one cross-word accumulator.
- The matrix accelerator has tile-level reuse but one scratchpad initiator.

These choices are intentional for the first correct baseline and are tracked in
[optimization_log.md](optimization_log.md).
