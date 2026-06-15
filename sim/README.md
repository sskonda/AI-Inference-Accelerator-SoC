# Simulation Organization

`verilator/` contains the cycle-accurate C++ harness, MMIO bus functional model,
external-memory model, trace control, and firmware binding. `scripts/` contains the
public simulator entry points used by the top-level Makefile.

The class-based testbench is kept under `uvm/` and is not passed to Verilator.

The regression runner writes one log per binary, seed, and initialization mode under
`logs/verilator/`. The SoC harness supports zero, one, and randomized startup values
through Verilator's runtime random-reset control. Architectural reset is applied before
every test.

```sh
make verilator-smoke SEED=1 INIT_MODE=zero
make verilator-regress SEEDS="1 7 19 41" INIT_MODES="zero ones random"
make verilator-smoke SEED=1 INIT_MODE=random TRACE=1
```

`TRACE=1` writes an FST waveform for the SoC harness under
`logs/verilator/traces/`. Other unit harnesses remain waveform-free to keep regressions
fast.
