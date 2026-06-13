# Simulation Organization

`verilator/` contains the cycle-accurate C++ harness, MMIO bus functional model,
external-memory model, trace control, and firmware binding. `scripts/` contains the
public simulator entry points used by the top-level Makefile.

The class-based testbench is kept under `uvm/` and is not passed to Verilator.
