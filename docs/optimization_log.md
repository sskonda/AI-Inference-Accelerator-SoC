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
| Matrix tile M/N | 2 | Provides source reuse without obscuring the control path |
| Scratchpad size | 64 KiB | Supports 16 firmware task slots |

## Attempts

| ID | Area | Status | Result |
| --- | --- | --- | --- |
| `baseline-rtl` | Correctness-first architecture | Kept | Establishes deterministic command, memory, and interrupt behavior |
| `baseline-metrics` | Measurement | Kept | Captures seed 1 CSV and JSON tables under `perf/results/` |
| `coverage-plumbing` | Verification quality | Kept | Adds instrumented Verilator coverage databases and summary reporting |

## Candidate List

The optimization phase will evaluate:

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

Accepted configurations will be summarized in
[performance_analysis.md](performance_analysis.md). Rejected configurations will remain
in this log with the measured reason.
