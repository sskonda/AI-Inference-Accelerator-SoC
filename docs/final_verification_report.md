# Final Verification Report

Date: June 15, 2026

## Scope

This report records the final local closure run for the simulation-only inference
accelerator SoC. The run covered open-source formatting, lint, firmware unit tests,
RTL lint, Verilator build, deterministic smoke and regression tests, available
coverage reporting, documentation checks, and static UVM structure checks.

The class-based UVM compile and execution commands were invoked. They did not run
because the local machine does not provide `vlog`, `vsim`, and `vlib`.

## Tool Versions

| Tool | Result |
| --- | --- |
| Git | `git version 2.43.0` |
| GNU Make | `GNU Make 4.3` |
| Python | `Python 3.12.3` |
| C++ compiler | `g++ (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0` |
| Verilator | `Verilator 5.020 2024-01-01 rev (Debian 5.020-1)` |
| Verible formatter | `Version v0.0-4071-g8d9f2c97` |
| Verible linter | `Version v0.0-4071-g8d9f2c97` |
| UVM simulator frontend | Not found: `vlog`, `vsim`, and `vlib` are absent |
| Optional synthesis estimator | Not found: `yosys` is absent |
| Verilator coverage annotator | Installed wrapper is unusable because its reporter binary is missing |

## Command Results

| Command | Result |
| --- | --- |
| `make fmt` | Pass: formatted 75 SystemVerilog files |
| `make lint` | Pass: Verible syntax and lint clean for 75 files |
| `make verilator-lint` | Pass: synthesizable RTL and harness tops lint clean |
| `make verilator-build` | Pass: all Verilator harness binaries built |
| `make verilator-smoke SEED=1 INIT_MODE=zero` | Pass: SoC, primitive, register, DMA, services, command, vector, reduction, and matrix smoke tests passed |
| `make verilator-regress` | Pass: seeded non-UVM regression passed |
| `make uvm-compile` | Not run: exited 2 because `vlog` is not on `PATH` |
| `make uvm-smoke` | Not run: exited 2 because `vlog` is not on `PATH` |
| `make uvm-regress` | Not run: exited 2 because `vlog` is not on `PATH` |
| `make coverage` | Pass: Verilator coverage databases and local summary generated |
| `make docs` | Pass: documentation, register map, and memory map checks passed |
| `make ci` | Pass: open-source closure suite passed |
| `python3 -m py_compile scripts/coverage/summarize_verilator_coverage.py scripts/perf/run_baseline.py scripts/docs/check_docs.py scripts/docs/check_register_map.py scripts/docs/check_memory_map.py scripts/lint/check_uvm.py` | Pass |
| `git diff --check` | Pass |
| Repository restricted-term scan | Pass: no tracked-content hits requiring removal |
| Repository stale-marker scan | Pass: no tracked-content placeholder markers |

The UVM targets fail closed with a clear missing-tool diagnostic. They are not counted
as passing local simulations.

## Seed List

| Suite | Seeds | Initialization modes |
| --- | --- | --- |
| Verilator smoke | `1` | `zero` |
| Verilator regression | `1`, `7`, `19`, `41` | `zero`, `ones`, `random` for the SoC top; unit harnesses use deterministic reset |
| Verilator coverage | `1`, `7`, `19`, `41` | `zero`, `ones`, `random` for the SoC top; unit harnesses use deterministic reset |
| UVM smoke and regression | Configured for `1`, `7`, `19`, `41` | Not executed locally because the simulator frontend is absent |

## Coverage Summary

`make coverage` produced 44 Verilator coverage databases under
`coverage/verilator`. The local text summary reported:

| Metric | Value |
| --- | ---: |
| Database bytes | 29,358,762 |
| Unique points | 31,096 |
| Covered points | 20,662 |
| Uncovered points | 10,434 |
| Point coverage | 66.45% |

The installed `verilator_coverage` wrapper cannot invoke its reporter binary on this
machine, so annotated HTML or source reports were not produced locally. The committed
coverage plan documents this as an environment limitation, not as a functional waiver.

UVM covergroups, cross coverage, sequences, monitors, scoreboards, and assertion bind
files are present and pass static structure checks. UVM coverage execution is pending an
environment with a compatible class-based simulator and UVM library.

## Assertion Summary

Verilator lint, build, smoke, regression, and coverage flows use `--assert`. No
assertion failures were observed in the available runs.

Assertion categories covered by the available runs include:

- valid/ready stable payload checks;
- FIFO and command queue overflow and underflow checks;
- DMA byte-count and completion checks;
- illegal register access and side-effect checks;
- interrupt pending, masking, and clear checks;
- timer tick checks;
- performance counter known-state checks;
- accelerator command sequencing and completion checks;
- memory fabric bounds and arbitration checks;
- SoC integration invariants.

Class-based assertion bind compilation remains not run locally because the UVM simulator
frontend is absent.

## Known Limitations

- The project is pure simulation. It does not include board support, physical
  implementation scripts, or timing closure.
- The local machine does not provide `vlog`, `vsim`, or `vlib`, so UVM compile and run
  targets were invoked but not executed.
- The optional synthesis estimator `yosys` is not installed locally.
- The installed Verilator coverage wrapper cannot locate its reporter binary; the local
  deterministic coverage summarizer was used instead.
- The external memory model is functional and deterministic, not a detailed DRAM timing
  model.
- The command processor issues one accelerator command at a time in the default
  configuration.

## Final Status

All available local checks passed. The UVM execution gap is fully attributed to missing
local simulator commands and is documented in the Makefile behavior, verification plan,
coverage plan, and known limitations.

No known functional bugs remain in the verified scope described above.
