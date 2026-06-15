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

## Baseline Capture

Milestone 17 captures the baseline with:

```sh
make perf-baseline SEED=1
```

The script runs the SoC, DMA, vector, reduction, and matrix Verilator harnesses in
`--test perf` mode and writes:

- `perf/results/baseline_metrics.csv`
- `perf/results/baseline_metrics.json`

The source revision column records the checked-out base revision at capture time. The
table was generated before the milestone 17 commit was created, so `source_dirty=true`
records that the performance-mode source edits were present in the worktree.

Measured verification-adjacent data from milestone 15:

| Metric | Value |
| --- | ---: |
| Verilator coverage databases | 44 |
| Unique coverage points | 31,280 |
| Covered coverage points | 20,856 |
| Point coverage | 66.68% |

These are coverage metrics, not throughput metrics.

## Baseline Throughput And Latency

The baseline results use deterministic seed 1.

| Workload | Size | Cycles | Stalled cycles | Derived rate |
| --- | ---: | ---: | ---: | ---: |
| DMA copy | 4 B | 4 | 2 | 1.0000 B/cycle |
| DMA copy | 16 B | 16 | 8 | 1.0000 B/cycle |
| DMA copy | 64 B | 64 | 32 | 1.0000 B/cycle |
| DMA copy with backpressure | 64 B | 154 | 126 | 0.4156 B/cycle |
| DMA memory-to-memory | 16 B | 16 | 8 | 1.0000 B/cycle |
| Vector add | 16 elements | 56 | 25 | 0.2857 elements/cycle |
| Vector multiply | 16 elements | 56 | 25 | 0.2857 elements/cycle |
| Vector ReLU | 16 elements | 40 | 17 | 0.4000 elements/cycle |
| Vector clamp | 16 elements | 56 | 25 | 0.2857 elements/cycle |
| Vector add with backpressure | 16 elements | 120 | 89 | 0.1333 elements/cycle |
| Vector scale | 16 elements | 42 | 18 | 0.3810 elements/cycle |
| Reduction sum | 16 elements | 26 | 10 | 0.6154 elements/cycle |
| Reduction maximum | 16 elements | 26 | 10 | 0.6154 elements/cycle |
| Reduction sum with backpressure | 16 elements | 51 | 36 | 0.3137 elements/cycle |
| Matrix multiply | 2x2x2 | 26 | 13 | 0.1538 outputs/cycle |
| Matrix multiply | 4x4x4 | 176 | 81 | 0.0909 outputs/cycle |
| Matrix multiply with backpressure | 4x4x4 | 361 | 281 | 0.0443 outputs/cycle |

The mixed firmware workload completed in 2,239 total cycles with 10 command
completions, 28 DMA completion events, 9 accelerator completion events, 347 bytes read,
347 bytes written, queue high-water mark 1, maximum interrupt latency 39 cycles, and
22.11% accelerator utilization over total SoC cycles.

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
