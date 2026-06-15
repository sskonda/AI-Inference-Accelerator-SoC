# Firmware

## Structure

The firmware layer is portable C++17 and depends only on the abstract `Mmio`
interface. The Verilator harness supplies the concrete cycle-accurate transport;
host unit tests use a deterministic register model.

| Path | Responsibility |
| --- | --- |
| `firmware/include/mmio.hpp` | MMIO and interrupt boundary |
| `firmware/include/hardware_drivers.hpp` | Driver APIs and command descriptor |
| `firmware/drivers/hardware_drivers.cpp` | DMA, accelerator, IRQ, timer, and counter drivers |
| `firmware/include/task.hpp` | Workload, phase, and task-state definitions |
| `firmware/include/cooperative_scheduler.hpp` | Workload submission and scheduler API |
| `firmware/rtos/cooperative_scheduler.cpp` | Priority selection, ISR dispatch, and stage transitions |
| `firmware/workloads/workload_api.cpp` | Workload validation and task construction |
| `firmware/tests/firmware_tests.cpp` | Host-side driver and scheduler tests |

## Driver Model

All register access goes through `Mmio::read` and `Mmio::write`. The drivers
program named constants from `soc_registers.hpp`; they do not contain duplicated
register addresses.

The DMA driver clears sticky status, programs source, destination, and exact byte
length, then starts the transfer with completion interrupts enabled. The
accelerator driver writes a complete descriptor before committing `CMD_SUBMIT`.
The interrupt driver manages enable, pending, and write-one-to-clear
acknowledgment. Timer and performance drivers provide periodic tick control and
coherent 64-bit counter reads.

## Task Model

Every task has one of these states:

- `READY`
- `RUNNING`
- `BLOCKED_ON_DMA`
- `BLOCKED_ON_ACCEL`
- `DONE`
- `ERROR`

Accelerator workloads advance through source loading, execution, and result
writeback. A task submits one hardware operation, enters a blocked state, and
does not execute again until the interrupt dispatcher observes completion.
DMA-copy tasks contain only one DMA stage.

Each task owns a 4 KiB scratchpad slot. The first 1 KiB holds source 0, the
second 1 KiB holds source 1, and the final 2 KiB holds output. Private slots let
one task stage DMA data while another task occupies an accelerator without
aliasing scratchpad buffers.

## Scheduler

`CooperativeScheduler::run_once` performs three actions:

1. Service pending enabled interrupts.
2. Wake or terminate the blocked task associated with the completed resource.
3. Dispatch the highest-priority ready task whose required resource is free.

Equal priorities preserve submission order. DMA and accelerator ownership are
tracked independently, so one DMA stage and one accelerator stage may overlap.
The baseline command processor supports one accelerator command in flight, and
the baseline DMA engine supports one transfer in flight.

The public workload APIs are:

- `submit_dma_copy`
- `submit_vector_add`
- `submit_vector_relu_or_clamp`
- `submit_reduce_sum`
- `submit_reduce_max`
- `submit_gemm`

The scheduler records submission and completion times, dispatch order,
completion order, timer ticks, and software scheduling stalls. A
`PerformanceSnapshot` reads the architectural counters for total cycles, DMA and
accelerator activity and stalls, queue high-water mark, completed commands,
bytes transferred, interrupt latency, and hardware scheduler stalls.

## Interrupt Handling

DMA completion wakes `BLOCKED_ON_DMA`. Command completion wakes
`BLOCKED_ON_ACCEL`; the accelerator-done source is acknowledged as a related
event but command completion remains the architectural retirement point. Timer
ticks increment a software count. Sticky hardware errors are read and cleared,
while operation-specific status determines whether the owning task reaches
`READY`, `DONE`, or `ERROR`.

## Verification

Run the host-side firmware tests with:

```sh
make firmware-test
```

The SoC executable links the same driver and scheduler sources. Its mixed
workload submits DMA, vector add, ReLU, clamp, sum, maximum, and matrix tasks at
different priorities. Results are checked against the independent C++ models
after interrupt-driven completion.
