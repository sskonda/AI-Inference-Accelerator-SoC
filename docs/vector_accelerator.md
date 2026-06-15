# Vector Accelerator

## Datapath

The vector accelerator processes packed 16-bit elements on the 32-bit memory interface,
so the default datapath completes two elements per result word. Element width, memory
width, and maximum vector length are parameters. Element width must be byte aligned and
must divide the memory width.

The accelerator accepts one command at a time and uses one memory initiator. Each result
word follows this sequence:

1. Read the first source word.
2. Read the corresponding second source word when required.
3. Execute every valid lane in parallel.
4. Write the packed result word.

The scale operation reads one scalar from lane zero at `src1_addr` before reading vector
data. ReLU does not read the second source. The final partial word enables only bytes
belonging to valid elements.

## Operations

| Opcode | Result |
| --- | --- |
| `VECTOR_ADD` | `src0[i] + src1[i]` |
| `VECTOR_MULTIPLY` | `src0[i] * src1[i]` |
| `VECTOR_SCALE` | `src0[i] * scalar`, scalar at `src1_addr` lane zero |
| `VECTOR_RELU` | signed maximum of `src0[i]` and zero; unsigned input passes through |
| `VECTOR_CLAMP` | clamp `src0[i]` to the inclusive range from zero through `src1[i]` |

`FLAG_SIGNED` selects signed two's-complement comparison and arithmetic. Arithmetic
results truncate to the element width by default. `FLAG_SATURATE` instead clamps add,
multiply, and scale results to the signed or unsigned element range. ReLU and clamp are
already range-limited and do not use the saturation flag.

For signed clamp, a negative upper bound produces zero. This keeps the specified lower
bound of zero valid for every element.

## Address Rules

All source, scalar, and destination addresses must be memory-word aligned and located in
scratchpad. Storage is rounded up to a complete memory word even when vector length is
not a multiple of the lane count. This rule removes read-boundary ambiguity and lets the
memory interface issue only aligned full-word reads.

Zero length, a length above the configured maximum, a non-vector opcode, misalignment,
or scratchpad overrun is rejected before memory traffic. A memory response error aborts
the command without issuing later accesses.

## Completion and Performance Events

`busy` remains asserted from command acceptance until the response is consumed. `done`
is a one-cycle pulse when the result or an error response is created. `error` and
`error_code` accompany failed completion.

`active_cycle` covers command execution but excludes response holding.
`stalled_cycle` identifies request backpressure, response latency, and completion
backpressure. `elements_completed_event` reports the number of elements committed by
each successful memory write.

## Verification

The Verilator suite compares every operation against the C++ reference model. Directed
tests cover signed and unsigned arithmetic, truncation, saturation, scalar loading,
negative ReLU inputs, clamp bounds, length one, odd length, maximum length, response
backpressure, memory stalls, illegal commands, memory errors, and reset during
execution. Seeded randomized tests vary operation, data, length, flags, and memory
timing.
