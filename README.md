# Inference Accelerator SoC

A pure-simulation SystemVerilog SoC for exploring command-driven accelerators,
firmware-controlled data movement, reusable verification, and computer-architecture
performance analysis.

The platform combines a five-channel AXI-Lite control interface, DMA, scratchpad SRAM,
a hardware command scheduler, interrupts, a timer, performance counters, and three
integer accelerators. C++ firmware programs the design through cycle-accurate MMIO,
submits workloads, blocks tasks on hardware completion, and services interrupts.

## Architecture

```mermaid
flowchart LR
  FW[C++ firmware and scheduler] -->|AXI-Lite MMIO| REGS[Register block]
  REGS --> DMA[DMA engine]
  REGS --> CQ[Command queue]
  CQ --> SCHED[Command scheduler]
  SCHED --> VEC[Vector engine]
  SCHED --> RED[Reduction engine]
  SCHED --> MAT[Matrix engine]
  DMA <--> DRAM[External memory model]
  DMA <--> SPM[Scratchpad SRAM]
  VEC <--> SPM
  RED <--> SPM
  MAT <--> SPM
  DMA --> IRQ[Interrupt controller]
  SCHED --> IRQ
  TIMER[Timer] --> IRQ
  IRQ --> FW
  DMA --> PERF[Performance counters]
  SCHED --> PERF
  VEC --> PERF
  RED --> PERF
  MAT --> PERF
```

The implementation is simulation-only. It does not include a physical-board flow or a
processor core. The firmware model is deliberately separated from RTL so a control core
can be attached at the MMIO and interrupt boundaries in a future revision.

## Planned Features

- Parameterized SystemVerilog RTL with shared packages and explicit interfaces.
- Valid/ready flow control with backpressure and protocol assertions.
- Read-first scratchpad SRAM and reusable FIFO/skid-buffer primitives.
- Exact-length DMA transfers between external memory and scratchpad.
- Round-robin and priority-first command scheduling with starvation protection.
- Signed integer vector, reduction, and tiled matrix operations.
- Timer, interrupt controller, sticky error reporting, and 64-bit counters.
- C++ drivers, task descriptors, cooperative scheduling, and ISR-style completion.
- Fast non-UVM simulation with a cycle-accurate C++ harness.
- UVM agents, constrained-random sequences, scoreboards, assertions, and coverage.
- Deterministic golden models and repeatable performance reports.

## Quick Start

List every public target:

```sh
make help
```

Run the open-source checks after Verible and Verilator are installed:

```sh
make fmt
make lint
make firmware-test
make verilator-lint
make verilator-build
make verilator-smoke
make verilator-regress
make docs
make ci
```

Run the class-based verification flow with a supported UVM simulator:

```sh
make uvm-compile
make uvm-smoke UVM_TEST=smoke_test UVM_SEED=1
make uvm-regress UVM_SEEDS="1 7 19 41"
make coverage
```

Targets never report success when a required tool or source artifact is absent. They
exit with a specific prerequisite message instead.

## Tool Requirements

| Purpose | Tool |
| --- | --- |
| Build orchestration | GNU Make and Bash |
| Documentation and regression scripts | Python 3 |
| Firmware and simulation harness | C++17 compiler |
| SystemVerilog formatting and lint | Verible |
| RTL lint and cycle-accurate simulation | Verilator |
| Class-based verification | Questa or compatible UVM simulator |
| Optional comparative synthesis estimates | Yosys |

The current environment audit is recorded in [docs/project_plan.md](docs/project_plan.md).
Architecture, verification scope, register behavior, and address regions are defined in
the `docs/` directory and evolve with each implementation milestone.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `rtl/` | Packages, interfaces, reusable blocks, accelerators, and SoC top |
| `firmware/` | Drivers, workload APIs, task model, and cooperative scheduler |
| `sim/verilator/` | C++ harness and behavioral memory |
| `sim/scripts/` | Simulator build and regression entry points |
| `uvm/` | Agents, environment, sequences, scoreboards, coverage, and tests |
| `models/` | C++ and Python reference models |
| `tests/` | Directed cases, random configurations, and regression manifests |
| `scripts/` | Formatting, lint, coverage, documentation, and performance tools |
| `docs/` | Architecture, interfaces, verification, and analysis |
| `perf/` | Reproducible configurations and committed result tables |

## Current Status

The architecture, command surface, shared packages, protocol interfaces, FIFO, skid
buffer, read-first RAM, scratchpad wrapper, AXI-Lite register block, and directed C++
regressions are implemented. The DMA engine adds exact byte-count copies, logical bursts,
full-range validation, error termination, and independent source/destination stalls.
Timer, sticky interrupt, interrupt-latency, and saturating performance-counter services
are also implemented. The shared-slot command queue adds round-robin and priority-first
selection, programmable starvation protection, occupancy tracking, and a tagged
single-inflight command processor. The packed-lane vector accelerator supports add,
multiply, scale, ReLU, and clamp with signed or unsigned truncating and saturating
arithmetic. The reduction accelerator uses a balanced lane tree and wide cross-word
accumulator for signed or unsigned sum and maximum operations. The tiled matrix
accelerator reuses loaded row and column elements across a 2-by-2 output tile and
supports signed or unsigned truncating and saturating products. The register block
supports independent write-address and write-data handshakes, partial writes, held
responses, sticky status, coherent counter reads, and atomic command submission.
The integrated SoC adds rotating single-outstanding arbitration across DMA and all
accelerators, internal scratchpad routing, external-memory routing, queued DMA command
adaptation, interrupt aggregation, and performance-event aggregation.
The C++ firmware layer provides typed DMA, accelerator, interrupt, timer, and performance
drivers; private per-task scratchpad slots; six workload-submission APIs; and a
priority-aware cooperative scheduler. Tasks block on DMA or accelerator completion and
resume through the interrupt dispatcher. The SoC regression runs a mixed seven-task
firmware workload and checks every result against the reference models.
Primitive timing is specified in
[docs/primitives.md](docs/primitives.md), DMA behavior in [docs/dma.md](docs/dma.md), and
system services in [docs/services.md](docs/services.md). Queue and scheduler behavior is
specified in [docs/command_scheduler.md](docs/command_scheduler.md), and vector arithmetic
in [docs/vector_accelerator.md](docs/vector_accelerator.md). Reduction behavior is
specified in [docs/reduction_accelerator.md](docs/reduction_accelerator.md), and matrix
behavior in [docs/gemm_accelerator.md](docs/gemm_accelerator.md). Additional RTL and
integration behavior in [docs/soc_integration.md](docs/soc_integration.md), and the
software architecture in [docs/firmware.md](docs/firmware.md). Additional verification
is introduced in gated milestones listed in [docs/project_plan.md](docs/project_plan.md).
Passing claims are made only for checks that have been executed with available tools.

## License

This project is available under the MIT License.
