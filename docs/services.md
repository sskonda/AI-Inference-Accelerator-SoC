# Timer, Interrupts, and Performance Counters

## Timer

The timer is a parameterized up-counter driven by `TIMER_CTRL`. An interval of zero
disarms the timer and produces no ticks. Enabling the timer or changing enable, periodic
mode, or interval restarts the count from zero.

For a nonzero interval, the timer asserts `tick` after that many active count cycles.
Periodic mode resets the count to zero and continues. One-shot mode holds the terminal
count and disarms after one tick; software rearms it by disabling and enabling the timer
or by changing its configuration. Disabling clears the visible value.

Only the count and timer control state reset. The timer has no free-running hidden epoch,
so every tick is reproducible from the visible configuration and value.

## Interrupt Controller

Five level-sensitive event inputs feed sticky pending bits:

| Bit | Source |
| ---: | --- |
| 0 | DMA completion |
| 1 | Command completion |
| 2 | Accelerator completion |
| 3 | Error |
| 4 | Timer tick |

The pending update is `(pending & ~clear) | sources`, so a source event wins over a clear
of the same bit. Pending state is independent of enable state. The external interrupt is
the reduction OR of enabled pending bits; disabled pending sources remain recorded
without asserting the external line.

The controller measures service wait cycles from external interrupt assertion until
software clears an enabled pending source. It emits a latency sample when service occurs.
If another enabled source remains pending, tracking restarts for the remaining service.
The latency counter saturates rather than wrapping.

## Performance Counters

The default implementation provides 64-bit saturating counters:

| ID | Counter | Update rule |
| ---: | --- | --- |
| 0 | Total cycles | Increment every cycle after reset |
| 1 | DMA active cycles | Increment on active event |
| 2 | DMA stalled cycles | Increment on stalled event |
| 3 | Accelerator active cycles | Increment on active event |
| 4 | Accelerator stalled cycles | Increment on stalled event |
| 5 | Queue high-water mark | Maximum observed occupancy |
| 6 | Commands completed | Increment on completion |
| 7 | Bytes read | Add exact byte event |
| 8 | Bytes written | Add exact byte event |
| 9 | Interrupt latency | Maximum observed latency sample |
| 10 | Scheduler stalls | Increment on stalled event |

IDs 11 through 15 read as zero. `PERF_SELECT` chooses one counter for the coherent
low/high read path in the register block. Global counter clear has priority over events
on the same edge. Saturation prevents a long simulation from silently wrapping a metric.

## Verification

Directed cycle-accurate tests cover:

- periodic intervals, interval one, one-shot mode, zero interval, disable, and restart;
- disabled pending interrupts, enable masking, persistence, selective clear, simultaneous
  sources, and source-versus-clear precedence;
- timer-to-interrupt propagation and interrupt service-latency measurement;
- every performance counter update class;
- queue and latency maximum tracking;
- reserved selector behavior;
- global clear;
- saturation using a reduced-width verification instance;
- reset state and no-unknown assertions.

The synthesizable lint configuration separately elaborates the architectural 24-bit
timer, 32-bit latency tracker, and 64-bit performance counters.
