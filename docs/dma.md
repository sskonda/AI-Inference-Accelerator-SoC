# DMA Engine

## Contract

The DMA engine copies between any two legal data regions through independent source-read
and destination-write memory ports. Source and destination addresses must be aligned to
the configured memory word width. Length is measured in bytes and may be any nonzero
value representable by `byte_count_t`.

A zero-length request is accepted and completes as a no-op without issuing memory
traffic. The complete source and destination ranges are validated before the first
request. An unaligned address, unsupported region, range overflow, or region-boundary
crossing completes with `ERR_ADDRESS` and does not access memory.

The engine provides `start_accepted` and `start_rejected` event outputs. A start while
busy is rejected with `ERR_DMA_BUSY`; the active transfer continues unchanged. `done`
and `error` are event pulses. Terminal memory response errors produce both events and
deassert `busy`.

## Microarchitecture

The baseline engine buffers one word and uses five control states:

1. Issue a source read request.
2. Wait for its response.
3. Capture the word and issue a destination write.
4. Wait for the write response.
5. Advance addresses and remaining byte count, or complete.

Only control, state, and event registers reset. Buffered data and active-transfer
datapath registers are loaded before use and have no reset path.

The final destination request enables only the low-order bytes still required. Source
reads remain full-word reads, so aligned endpoints and word-sized legal regions guarantee
that the final read stays in bounds. Read and write event counts report the exact logical
byte count, including a partial final word.

## Bursts and Backpressure

`MAX_BURST_BEATS` sets the maximum logical burst length. `req_last` is asserted on every
configured burst boundary and on the final transfer beat. The baseline memory interface
still permits one request in flight; logical bursts expose grouping to monitors and a
future arbiter without assuming unsupported outstanding responses.

Request valid and payload remain stable under request backpressure. Response ready is
asserted only in the corresponding response state. Source request stalls, source
response latency, destination request stalls, and destination response latency all
contribute to `stalled_cycle`. `active_cycle` follows `busy`.

## Copy Semantics

Scratchpad-to-memory, memory-to-scratchpad, scratchpad-to-scratchpad, and
memory-to-memory copies are legal. The copy proceeds from low to high addresses.
Overlapping source and destination ranges have ordinary `memcpy` semantics and are not
guaranteed to preserve the original source bytes.

## Verification

The cycle-accurate test model checks:

- one-word and multiword transfers;
- partial final-word strobes and untouched neighboring bytes;
- logical burst boundaries;
- independent source and destination request stalls;
- independent response latency;
- zero length;
- unaligned, illegal-region, and boundary-crossing requests;
- source and destination response errors;
- a second start while busy;
- reset while a request is stalled;
- back-to-back transfers;
- all supported source/destination region combinations;
- randomized lengths, data, latency, and backpressure.

The scoreboard compares destination bytes against an independent byte-vector reference
and checks exact read/write event totals and request counts.
