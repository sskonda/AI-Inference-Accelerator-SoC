# Command Queue and Scheduler

## Queue Organization

The command queue uses eight shared slots by default. Queue depth, occupancy width, and
starvation-counter width are parameters. Descriptor storage is not reset; reset clears
the valid vector, occupancy, high-water mark, selection lock, and round-robin pointer so
no stale descriptor can become visible.

An enqueue is accepted only when the queue is not full. The queue intentionally does not
accept a replacement enqueue during a full-queue dequeue cycle. This matches the command
interface invariant that no command handshake occurs while `full` is asserted and keeps
software-visible full behavior unambiguous.

The selected descriptor is held stable whenever the processor applies backpressure.
Enqueues, priority changes, and age changes cannot replace a locked selection. A dequeue
advances the round-robin starting slot and releases the lock.

## Scheduling Policies

`SCHED_CTRL.POLICY` selects one of two policies:

- Round-robin scans occupied slots beginning at the slot after the previous dequeue.
  Priorities do not affect selection.
- Priority-first selects the highest numeric priority. Equal-priority commands use
  greatest wait age, then lowest slot index.

Every valid entry has a saturating wait-age counter. In priority-first mode, a nonzero
starvation threshold overrides priority when at least one entry reaches the threshold.
The greatest-age threshold-qualified entry is selected. A zero threshold disables the
starvation override.

The policy is applied only when execution is enabled. This lets firmware stage a batch
before allowing the scheduler to choose the first descriptor.

## Command Processor

The baseline command processor allows one command in flight. It routes opcodes as follows:

| Executor | Opcodes |
| --- | --- |
| DMA | `DMA_COPY` |
| Vector | `VECTOR_ADD`, `VECTOR_MULTIPLY`, `VECTOR_SCALE`, `VECTOR_RELU`, `VECTOR_CLAMP` |
| Reduction | `REDUCE_SUM`, `REDUCE_MAX` |
| Matrix | `GEMM` |

An invalid opcode is removed from the queue and returned as a tagged `OPCODE` error
without reaching an executor. A legal descriptor remains selected until the target
executor accepts it. The processor then waits for a matching command ID and opcode,
captures one completion, and holds the response stable until consumed.

Executor-provided nonzero cycle counts are retained. A zero executor count is replaced
by the processor's saturating measured latency. Completion and error events are
single-cycle pulses generated when a response is captured.

Only one in-flight command is a correctness-first baseline. It avoids response
reordering before the accelerator protocols and scoreboards are integrated. Increasing
concurrency is an explicit optimization candidate.

## Assertions and Coverage

Assertions check:

- stable enqueue and dequeue payloads under backpressure;
- no overflow, underflow, or out-of-range occupancy;
- selected-slot validity and legal scheduler policy;
- legal processor state and one-hot dispatch;
- one-hot executor responses and matching response tags;
- response stability and no queue acceptance while busy.

Cover properties track every occupancy level, empty/full transitions, both policies,
starvation override, every executor route, invalid opcode handling, and executor errors.

The Verilator command regression checks reset with queued work, empty/full status,
high-water mark, stalled dispatch stability, back-to-back routing, round-robin order,
priority order, starvation override, invalid opcodes, all legal opcodes, response
backpressure, error propagation, and 200 seeded random command completions per run.
