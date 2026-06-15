# Test Organization

`regressions/` contains suite manifests consumed by simulation scripts. Directed and
seeded-random cases are implemented in the Verilator harnesses and UVM sequence library,
not as separate data files.

Runtime logs are written under `logs/verilator/`. Optional FST waveforms are written
under `logs/verilator/traces/`. These runtime artifacts are not committed.
