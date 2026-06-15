# Test Organization

- `directed/` contains named corner-case configurations.
- `random/` contains constrained configuration ranges and deterministic seed lists.
- `regressions/` contains suite manifests consumed by simulation scripts.
- `data/` contains small text fixtures whose provenance and expected results are
  documented.

Runtime logs are written under `logs/verilator/`. Optional FST waveforms are written
under `logs/verilator/traces/`. These runtime artifacts are not committed.
