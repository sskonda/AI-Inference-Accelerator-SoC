# Optimization Log

## Policy

Optimization starts only after the baseline architecture is functionally complete and the
baseline performance run is reproducible. Each optimization must:

- change one design variable at a time;
- record the before and after measurement method;
- run the full available regression;
- keep the change only when it improves performance, maintainability, verification
  quality, or implementation quality without an unacceptable tradeoff;
- leave rejected attempts documented.

## Current Default Configuration

| Parameter | Default | Rationale |
| --- | ---: | --- |
| DMA logical burst beats | 4 | Exposes burst boundaries while retaining one outstanding request |
| Command queue depth | 8 | Enough to exercise full/empty behavior and mixed workload contention |
| Starvation threshold | 16 | Prevents indefinite priority blocking in priority-first mode |
| Vector maximum length | 256 | Large enough for randomized coverage and small enough for fast simulation |
| Reduction maximum length | 256 | Matches vector bounds and accumulator validation |
| Matrix maximum M/N/K | 8 | Supports directed and randomized small matrices |
| Matrix tile M/N | 4 | Improves source reuse for simulation-friendly matrices |
| Scratchpad size | 64 KiB | Supports 16 firmware task slots |

## Attempts

| ID | Area | Status | Result |
| --- | --- | --- | --- |
| `baseline-rtl` | Correctness-first architecture | Kept | Establishes deterministic command, memory, and interrupt behavior |
| `baseline-metrics` | Measurement | Kept | Captures seed 1 CSV and JSON tables under `perf/results/` |
| `coverage-plumbing` | Verification quality | Kept | Adds instrumented Verilator coverage databases and summary reporting |
| `gemm-tile-4x4` | Matrix tile shape | Kept | Reduces 4x4 matrix cycles from 176 to 100 and backpressured 4x4 cycles from 361 to 217 |

## Explored Configurations

| Configuration | Result | Decision |
| --- | --- | --- |
| 2-by-2 matrix tile | Baseline: 4x4 matrix uses 176 cycles and 64 source reads | Replaced by 4-by-4 default |
| 4-by-4 matrix tile | 4x4 matrix uses 100 cycles and 32 source reads | Kept as default |

The 4-by-4 default increases tile accumulator storage, but the configured matrix limits
remain small and all available regressions pass. The improvement is concentrated on
matrix workloads; DMA, vector, and reduction results remain unchanged.

## Remaining Candidate List

The optimization phase accepted the 4-by-4 matrix tile as the default. Remaining
candidates for future comparison are:

- FIFO depths and skid-buffer placement.
- DMA logical burst length and buffering.
- Command queue depth and scheduler threshold.
- Scratchpad banking or address layout.
- Matrix tile shape and accumulation structure.
- Vector pipeline depth.
- Reduction tree shape for wider memory words.
- Register placement and high-fanout control reduction.
- Memory fabric outstanding depth.
- Verilator runtime improvements that preserve coverage.

Accepted configurations are summarized in
[performance_analysis.md](performance_analysis.md). Future rejected configurations should
remain in this log with the measured reason.
