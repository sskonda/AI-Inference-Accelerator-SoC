# Coverage Plan

## Scope

Coverage closure is split into two complementary views:

- Verilator assertion and structural coverage for the synthesizable RTL and C++ harnesses.
- UVM functional coverage for protocol, scheduler, interrupt, command, and workload
  interactions when a compatible simulator is available.

The local milestone 15 closure uses Verilator coverage because it is available in this
environment. UVM covergroups are implemented and statically checked, but simulator
execution remains not run locally without `vlog`, `vsim`, and a UVM library.

## RTL Assertion Coverage

Assertions are enabled in Verilator lint, build, smoke, regression, and coverage runs.
The planned assertion categories are implemented across the following blocks:

| Category | RTL location |
| --- | --- |
| Valid/ready stable payload | `rtl/interfaces`, `rtl/fifo`, `rtl/common`, command paths |
| FIFO and command queue bounds | `rtl/fifo/sync_fifo.sv`, `rtl/command_queue/command_queue.sv` |
| DMA byte bounds and completion | `rtl/dma/dma_engine.sv`, `rtl/dma/dma_command_adapter.sv` |
| Register side effects | `rtl/regs/soc_register_block.sv` |
| Interrupt persistence and masking | `rtl/irq/irq_controller.sv` |
| Timer expiration | `rtl/timer/soc_timer.sv` |
| Counter known-state behavior | `rtl/perf/performance_counters.sv` |
| Accelerator command and output sequencing | `rtl/accel/*/*_accelerator.sv` |
| Memory fabric arbitration and bounds | `rtl/memory/soc_memory_fabric.sv` |
| SoC integration invariants | `rtl/soc/soc_top.sv` |

## Verilator Coverage Points

The open-source coverage run builds instrumented simulators under
`build/verilator_coverage` and executes the same seeded regression used by the normal
Verilator flow. The coverage run writes per-binary databases under `coverage/verilator`
and a text report under `coverage/summary.txt`.

Milestone 15 local results:

| Metric | Value |
| --- | ---: |
| Coverage databases | 44 |
| Database bytes | 29,595,285 |
| Unique coverage points | 31,280 |
| Covered coverage points | 20,856 |
| Uncovered coverage points | 10,424 |
| Point coverage | 66.68% |

The installed `verilator_coverage` wrapper cannot locate its reporter binary in this
environment, so `make coverage` records that condition and emits a deterministic local
summary from the databases. The raw databases remain available for a working
`verilator_coverage --annotate` installation.

Top-level RTL cover properties observe:

- DMA completion.
- Command completion.
- Vector, reduction, and matrix accelerator completion.
- Timer ticks.
- Command queue full state.
- Command queue drain from nonempty to empty.
- Memory-fabric error observation.

Block-level cover properties observe:

- Command dispatch to every executor class.
- Command queue occupancy levels, full and empty transitions, scheduler policy, and
  starvation override.
- Vector opcodes, signed and unsigned modes, maximum length, stalled memory cycles, and
  memory errors.
- Reduction sum, maximum, odd length, maximum length, stalled memory cycles, and memory
  errors.
- Matrix dimensions, partial tiles, maximum dimensions, stalled memory cycles, and memory
  errors.

## UVM Functional Coverage

The UVM coverage collector defines covergroups for:

- Register access direction and offset.
- Command opcode, priority, and command ID class.
- DMA length, alignment, and backpressure class.
- Scheduler policy and queue occupancy class.
- External-memory latency, backpressure, write enable, byte enable, and error injection.
- Interrupt assertion, deassertion, and pending/enable/clear combinations.
- Architectural error status values.

Planned cross coverage focuses on interactions with high defect risk:

- Opcode by scheduler policy.
- DMA length class by memory backpressure class.
- Interrupt source by enable and clear behavior.
- Queue occupancy by command priority.
- Error code by operation class.

## Closure Status

| Item | Status |
| --- | --- |
| Verilator assertions | Passing in the available regression after milestone 14 |
| Verilator coverage target | Passing in milestone 15 with the local summary fallback |
| UVM covergroups | Implemented and statically checked |
| UVM coverage execution | Not run locally because a compatible simulator is unavailable |
| Waived bins | None |

The UVM bins are not waived. They are pending execution in an environment with a
class-based simulator and UVM library.

## Reproduction

Run:

```sh
make coverage
```

The default seeds are `1`, `7`, `19`, and `41`; the default SoC initialization modes are
`zero`, `ones`, and `random`. Override them with:

```sh
make coverage SEEDS="1 7 19 41" INIT_MODES="zero ones random"
```
