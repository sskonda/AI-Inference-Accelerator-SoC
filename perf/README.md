# Performance Results

Performance configurations, scripts, and committed machine-readable result tables live
under this directory. Each result records the source revision, configuration, seed,
counter values, and command dimensions required for reproduction.

Baseline data is captured before optimization. Later experiments retain both accepted
and rejected configurations so the selected default can be justified by measured
tradeoffs.

Run the baseline capture with:

```sh
make perf-baseline SEED=1
```

The committed baseline tables are:

- `perf/results/baseline_metrics.csv`
- `perf/results/baseline_metrics.json`
