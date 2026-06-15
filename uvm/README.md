# UVM Organization

The class-based environment is separated into packages, interfaces, reusable agents,
environment configuration, virtual sequences, scoreboards, coverage, assertion binds,
and tests.

The AXI-Lite agent implements the exact single-beat subset documented by this project.
The memory agent can inject latency and backpressure while maintaining a byte-addressable
mirror. Scoreboards consume monitor transactions rather than peeking at driver state.

## Components

| Component | Responsibility |
| --- | --- |
| AXI-Lite agent | Drives and monitors independent AW, W, B, AR, and R handshakes |
| Memory agent | Responds to RTL requests with configurable readiness, latency, and errors |
| Command agent | Observes tagged command completion, opcode, error, and queue occupancy |
| IRQ agent | Observes external interrupt assertion and deassertion |
| Virtual sequencer | Coordinates MMIO, memory initialization, reset, and expectations |
| Scoreboard | Checks memory bytes, command conservation, completion identity, and errors |
| Reference model | Computes vector, reduction, and matrix expected values |
| Coverage collector | Samples registers, commands, DMA, scheduling, memory, IRQ, and errors |
| Assertion bind | Adds SoC-level reset, protocol, completion, and output checks |

The scoreboard receives only monitor transactions. Virtual sequences use its expectation
API before starting a workload, but they do not inject observed results. The command
monitor uses explicit SoC debug outputs so sticky status bits cannot be mistaken for
multiple completions.

## Tests

`tests/regressions/uvm_tests.txt` is the canonical ordered regression list. It contains
register, DMA, vector, reduction, matrix, command-queue, interrupt, reset, backpressure,
mixed-workload, error-injection, performance-counter, and smoke tests. Directed tests
target architectural corner cases; random tests derive data and dimensions from the
simulator seed.

## Running

First validate source organization and factory registration without a simulator:

```sh
make uvm-check
```

For a Questa-compatible simulator, ensure `vlib`, `vlog`, and `vsim` are on `PATH`. If
needed, set `UVM_HOME` to the source directory containing `uvm_pkg.sv`:

```sh
export UVM_HOME=/path/to/uvm/src
make uvm-compile
make uvm-smoke UVM_TEST=smoke_test UVM_SEED=1
make uvm-regress UVM_SEEDS="1 7 19 41"
```

Each simulation log is written under `logs/`. A run passes only when the simulator exits
successfully and its report summary contains zero UVM errors and zero UVM fatals.

## Local Status

The current environment does not provide a compatible UVM simulator. The static UVM
structure, source ordering, required classes, factory registrations, and regression
manifest are checked by `make uvm-check`; compile and runtime status remain not run.
