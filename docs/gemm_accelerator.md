# GEMM Accelerator

## Datapath

The GEMM accelerator computes a row-major matrix product `C = A * B` from scratchpad.
The default configuration supports dimensions from one through eight and produces a
2-by-2 output tile at a time. Matrix element width, accumulator width, dimension limits,
and tile shape are parameters.

For each output tile and inner-dimension index, the controller:

1. Reads one element from each valid tile row of matrix A.
2. Reads one element from each valid tile column of matrix B.
3. Updates every valid tile accumulator in parallel.
4. Repeats for the complete inner dimension.
5. Writes each completed output element with byte strobes.

This organization reuses each loaded A value across the tile columns and each loaded B
value across the tile rows. Partial edge tiles suppress inactive rows and columns. The
baseline uses one backpressured memory initiator and permits one command in flight.

## Layout and Address Rules

Matrices use compact row-major 16-bit elements:

- A contains `M * K` elements.
- B contains `K * N` elements.
- C contains `M * N` elements.

Each matrix base must be memory-word aligned and its rounded storage range must remain
inside scratchpad. The destination range may not overlap either input range. Inputs may
share storage because they are read-only. Element accesses are converted to aligned
memory-word reads, and lane selection chooses the requested element. Output writes
enable only the two bytes belonging to the selected element.

Zero dimensions, dimensions above their configured maxima, a non-GEMM opcode,
misalignment, scratchpad overrun, or output overlap is rejected before memory traffic.
A memory response error terminates the command and suppresses later accesses.

## Precision

`FLAG_SIGNED` selects signed two's-complement multiplication and accumulation. Otherwise,
elements are unsigned. Every tile accumulator uses `ACCUM_WIDTH`; parameter validation
requires enough bits for the configured element width and maximum inner dimension.

The final accumulator truncates to element width by default. With `FLAG_SATURATE`, it
clamps to the signed or unsigned 16-bit result range. Conversion occurs only after the
complete inner dimension has accumulated.

## Completion and Performance Events

`busy` remains asserted from command acceptance until the tagged response is consumed.
`done` is a one-cycle pulse when a success or error response is created. A successful
response reports `M * N` in `result`.

`active_cycle` covers matrix execution and excludes response holding. `stalled_cycle`
identifies request backpressure, response latency, and completion backpressure.
`outputs_completed_event` reports one for each committed output element. The final
memory write alone asserts `req_last`.

## Verification

The Verilator suite compares every output against an independent C++ model. Directed
tests cover 1-by-1, square, rectangular, inner dimension one, zero, identity-like,
signed minimum and maximum values, truncation, saturation, partial tiles, maximum
dimensions, memory delay, response backpressure, illegal descriptors, overlap,
scratchpad bounds, memory errors, and reset during execution. Seeded randomized tests
vary all dimensions, values, arithmetic flags, and memory timing.

The harness also checks exact read and write counts, aligned requests, byte strobes,
matrix padding preservation, final-write marking, and the source-read reduction from
tile reuse.
