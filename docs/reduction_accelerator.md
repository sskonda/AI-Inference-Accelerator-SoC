# Reduction Accelerator

## Datapath

The reduction accelerator reads packed scratchpad words through one backpressured memory
initiator. Lanes within each word feed a balanced binary tree. The tree produces a
word-level sum and maximum, and a sequential accumulator combines those partial results
across words.

The lane count must be a power of two. The default 32-bit memory word contains two 16-bit
lanes and therefore uses one tree level. Wider parameterizations add logarithmic tree
levels rather than extending a linear arithmetic chain.

Only one result word is written. Lane zero contains the reduced element and the remaining
bytes retain their previous scratchpad values through byte strobes.

## Operations and Precision

| Opcode | Behavior |
| --- | --- |
| `REDUCE_SUM` | Sum every source element in a wide accumulator |
| `REDUCE_MAX` | Select the greatest source element |

`FLAG_SIGNED` selects signed two's-complement extension and comparison. Sum uses
`ACCUM_WIDTH` for all tree and cross-word arithmetic; the default 40-bit accumulator is
wider than required by the default 16-bit, 256-element configuration. The accumulator
width is validated against the configured maximum length.

The final sum truncates to element width unless `FLAG_SATURATE` is set. Saturation clamps
to the signed or unsigned element range. Maximum always returns an existing element, so
the saturation flag has no effect on that operation.

## Command and Address Rules

`src0_addr` identifies the packed input and `dst_addr` identifies the result word. Both
addresses must be memory-word aligned and wholly inside scratchpad. Input storage rounds
up to a complete memory word for odd lengths. Length must be from one through the
configured maximum.

An invalid opcode, dimension, alignment, or range is rejected before memory traffic.
A memory response error terminates the command and suppresses later accesses.

## Completion and Performance Events

`busy` remains asserted until the tagged response is consumed. `done` pulses when the
result or error response is created. `active_cycle` covers execution and
`stalled_cycle` identifies memory or response backpressure.
`elements_completed_event` reports the full input length after the result write commits.

## Verification

The Verilator suite compares RTL against an independent C++ model. Directed cases cover
length one, odd and power-of-two lengths, maximum length, negative signed values,
unsigned values, truncating and saturating overflow, both operations, memory delay,
response backpressure, illegal descriptors, memory errors, and reset during execution.
Seeded random cases vary data, operation, length, flags, and memory timing.
