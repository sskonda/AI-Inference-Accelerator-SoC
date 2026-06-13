# Project Plan

## Repository Audit

Audit date: June 13, 2026.

The repository is an existing Git repository with one initial commit and a
single tracked README. The worktree was clean before this plan was added.

| Item | Result |
| --- | --- |
| Current branch | `main` |
| Remote | SSH `origin` |
| Remote default branch | `main` |
| Local tracking | `main` tracks `origin/main` |
| Remote connectivity | Read access confirmed |
| Configured author | `Sanat Konda <sskonda04@gmail.com>` |
| Git | 2.43.0 |
| GNU Make | 4.3 |
| Python | 3.12.3 |
| C++ compiler | GNU C++ 13.3.0 |
| Verilator | Not installed |
| Verible formatter and linter | Not installed |
| UVM-capable simulator | Not installed |
| Yosys | Not installed |

The configured author identity is a human identity and will be used unchanged.
Every milestone is performed directly on `main`. A failed push is a hard stop:
the local commit is retained, the failure is reported, and later milestones are
not started.

## Architecture Summary

The project is a pure-simulation, firmware-controlled heterogeneous accelerator
SoC. A five-channel AXI-Lite subset provides MMIO control. Firmware running in
the C++ simulation harness configures a DMA engine, submits descriptors to a
hardware command queue, blocks tasks on completion, services interrupts, and
records performance data.

The datapath contains:

- A byte-addressable external memory model with deterministic initialization,
  configurable response latency, and backpressure.
- A portable, read-first scratchpad SRAM with explicit read-during-write
  behavior.
- A DMA engine for external-memory, scratchpad, and supported memory-copy
  paths.
- A command queue and scheduler supporting round-robin and priority-first
  policies with starvation protection.
- Vector add, scale, multiply, clamp, and rectification operations.
- Signed integer sum and maximum reductions.
- A small tiled signed-integer matrix multiplication engine.
- Timer, interrupt controller, error reporting, and architectural performance
  counters.

Shared packages define widths, address regions, register offsets, opcodes,
descriptor layouts, response types, errors, and counter identifiers. Interfaces
define all handshakes and provide protocol assertions. Each accelerator uses
separate control and datapath logic where that separation makes the intended
circuit clearer.

The first implementation favors simple, measurable correctness. Performance
work begins only after system integration, firmware execution, UVM structure,
and non-UVM regressions exist.

## Coding Method

RTL follows a circuit-first method:

1. Define the interface, storage elements, datapath, state transitions, and
   cycle-level behavior before coding a block.
2. Use `always_ff` with nonblocking assignments for sequential logic.
3. Use `always_comb` with blocking assignments and complete defaults for
   combinational logic.
4. Use two-process finite-state machines with explicit enum state types.
5. Reset control, valid, state, counters, and required architectural state;
   avoid resetting inferred memory arrays and unnecessary datapath registers.
6. Use explicit widths and conversions to prevent accidental truncation,
   extension, signedness changes, or implicit nets.
7. Use read-first portable RAM templates and specify collision behavior.
8. Keep testbench driving and sampling synchronized to avoid event-order races.
9. Combine assertions, reference models, scoreboards, and functional coverage;
   use a simpler queue or software model when an assertion would be needlessly
   difficult to maintain.

These practices align with the referenced SystemVerilog tutorial's
synthesizable RTL, RAM, race-avoidance, assertion, coverage, constrained-random,
and UVM examples.

## Milestones

Each milestone ends with its required checks, status review, commit, push, and
post-push status review.

| Milestone | Deliverable | Commit subject |
| --- | --- | --- |
| 0 | Repository audit and project plan | `milestone 0: project plan and repository audit` |
| 1 | Build system, scripts, skeleton, and initial documentation | `milestone 1: build system and project skeleton` |
| 2 | Shared packages, interfaces, protocols, and interface assertions | `milestone 2: common packages and interfaces` |
| 3 | FIFO, skid buffer, RAM, scratchpad, and primitive tests | `milestone 3: FIFO and RAM primitives` |
| 4 | AXI-Lite register block and register tests | `milestone 4: MMIO register block` |
| 5 | DMA engine, assertions, counters, and transfer tests | `milestone 5: DMA engine` |
| 6 | Timer, interrupt controller, and performance counters | `milestone 6: timer interrupts and performance counters` |
| 7 | Command queue, descriptor tracking, and scheduler | `milestone 7: command queue and scheduler` |
| 8 | Vector accelerator and golden-model tests | `milestone 8: vector ALU accelerator` |
| 9 | Reduction accelerator and golden-model tests | `milestone 9: reduction accelerator` |
| 10 | Tiled matrix accelerator and golden-model tests | `milestone 10: GEMM accelerator` |
| 11 | Integrated SoC top and system smoke tests | `milestone 11: SoC top integration` |
| 12 | Firmware drivers, task model, ISR model, and scheduler | `milestone 12: firmware and RTOS scheduler` |
| 13 | Reusable UVM environment, tests, scoreboard, and coverage | `milestone 13: UVM verification environment` |
| 14 | C++ Verilator harness and deterministic regressions | `milestone 14: Verilator harness and regressions` |
| 15 | Assertion review and functional coverage closure | `milestone 15: assertions and coverage closure` |
| 16 | Complete architecture, firmware, verification, and user documentation | `milestone 16: documentation` |
| 17 | Reproducible baseline performance results | `milestone 17: baseline performance metrics` |
| 18 | Measured, regression-protected optimization pass | `milestone 18: optimization pass` |
| 19 | Full available verification and closure report | `milestone 19: final verification closure` |
| 20 | Repository consistency and presentation review | `milestone 20: final polish` |

Accepted optimization experiments may receive additional milestone 18 commits,
one per independently measured improvement, before the final optimization-pass
commit.

## Verification Strategy

Verification is layered so failures are localized early:

1. Static checks validate formatting, syntax, lint, parameter widths, and the
   synthesizable source set.
2. Directed primitive tests close reset, boundary, simultaneous-operation, and
   read-during-write behavior before those primitives are integrated.
3. The C++ harness provides fast cycle-accurate module and SoC tests through
   actual MMIO, memory, interrupt, and firmware paths.
4. Deterministic golden models check every accelerator result and DMA copy.
5. Randomized regressions vary data, dimensions, delays, backpressure, reset
   timing, queue pressure, initialization, and seeds.
6. UVM agents independently drive and monitor MMIO and memory traffic. The
   scoreboard checks data, descriptors, interrupts, and memory integrity.
7. Assertions cover valid/ready stability, legal state, bounds, queue safety,
   command conservation, completion ordering, and interrupt persistence.
8. Functional coverage tracks registers, operations, dimensions, lengths,
   occupancy, scheduler policies, errors, resets, stalls, and relevant crosses.
9. Performance tests produce machine-readable results from architectural
   counters and compare selected configurations.

Closure means all checks supported by the installed tools pass, no known
functional failures remain, assertions pass, planned bins are covered or
specifically justified, warnings are resolved or documented, and every omitted
commercial-simulator result is labeled not run rather than passed.

## Tool Strategy

- Verible is the authority for SystemVerilog formatting and style lint.
- Verilator checks synthesizable RTL and builds the C++ simulation executable.
  It does not compile the class-based UVM environment.
- A UVM-capable simulator runs the class-based environment when available.
  The scripts auto-detect supported simulators and fail with a precise
  installation message when none is present.
- GNU C++ builds firmware, golden models, memory models, and unit tests.
- Python scripts coordinate deterministic regressions, documentation checks,
  coverage summaries, and performance result processing.
- Yosys is optional and is used only for comparative synthesis estimates when
  installed. No physical-board flow is part of the project.
- Continuous integration installs the required open-source tools and executes
  the same public Make targets used locally.

Missing local tools are not treated as successful checks. During development,
open-source tool gaps may be resolved with local tool installations that do not
alter repository behavior. Commercial simulator availability remains an
explicit environmental limitation.

## Expected Limitations

- No CPU core is included. The control core is modeled by C++ firmware issuing
  cycle-accurate MMIO transactions.
- No physical implementation, board flow, vendor block design, timing closure,
  or silicon area claim is provided.
- The external memory model is behavioral and intentionally smaller than a
  production DRAM controller.
- AXI-Lite implements the documented single-beat subset; it is not an AXI
  interconnect or full protocol implementation.
- Accelerator dimensions and memory sizes are bounded for practical simulation
  runtime.
- Arithmetic is integer or fixed-width signed arithmetic with documented
  overflow, truncation, and saturation behavior.
- UVM compile, simulation, and coverage cannot be claimed locally until a
  compatible simulator is installed.
- Synthesis estimates are comparative only and are unavailable locally until
  Yosys is installed.
- A future control-core port may attach a RISC-V core at the MMIO and interrupt
  boundaries without changing accelerator command semantics.

## User Commands

The final public interface is:

```sh
make help
make fmt
make lint
make verilator-lint
make verilator-build
make verilator-smoke
make verilator-regress
make uvm-compile
make uvm-smoke
make uvm-regress
make coverage
make docs
make clean
make ci
```

Common focused invocations are:

```sh
make verilator-smoke SEED=1
make verilator-regress SEEDS="1 7 19 41"
make uvm-smoke UVM_TEST=smoke_test UVM_SEED=1
make uvm-regress UVM_SEEDS="1 7 19 41"
make coverage
make docs
```

The full local closure sequence is:

```sh
make fmt
make lint
make verilator-lint
make verilator-build
make verilator-smoke
make verilator-regress
make uvm-compile
make uvm-smoke
make uvm-regress
make coverage
make docs
make ci
```

Until Milestone 1 creates the Makefile, the Milestone 0 audit can be reproduced
with:

```sh
git status --short --branch
git branch --show-current
git remote -v
git remote show origin
git config user.name
git config user.email
git --version
make --version
python3 --version
g++ --version
command -v verilator
command -v verible-verilog-format
command -v verible-verilog-lint
command -v vsim
command -v yosys
git diff --check
```
