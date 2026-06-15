# SoC Integration

## Top-Level Boundary

`rtl/soc/soc_top.sv` exposes three simulation-facing interfaces:

1. A flattened five-channel AXI-Lite control port.
2. A valid/ready external-memory request and response port.
3. A level-sensitive interrupt output.

Debug outputs report aggregate busy state, completion pulses, memory-fabric activity,
queue occupancy, sticky error state, and a definition checksum. They are observability
signals only and do not affect architectural behavior.

## Command Path

Firmware stages a descriptor in the register block and writes `CMD_SUBMIT`. The command
queue stores complete descriptors and selects them with round-robin or priority-first
policy. The command processor permits one queued command in flight and routes it to DMA,
vector, reduction, or GEMM execution.

The DMA command adapter converts a queued `DMA_COPY` descriptor into the DMA engine's
start interface and returns a tagged response. Direct MMIO DMA starts share the same
engine. A direct start has priority in a cycle where both sources request an idle engine;
the command path remains backpressured and is not dropped.

All accelerator responses pass through the command processor before the register block
sets sticky command status. Command ID and opcode are checked by assertions at the
processor boundary.

## Memory Fabric

The memory fabric arbitrates five initiators:

- DMA source;
- DMA destination;
- vector accelerator;
- reduction accelerator;
- GEMM accelerator.

It supports one outstanding transaction and uses rotating priority after every accepted
request. Arbitration creates a registered grant and latches the complete request before
asserting `ready`. This prevents combinational ready-to-valid paths and holds address,
direction, write data, byte strobes, and final-beat indication stable through stalls.

Scratchpad addresses route to the internal 64 KiB read-first RAM. External-memory
addresses route to the top-level request/response interface. Misaligned, out-of-range,
or unmapped word requests complete locally with an error response. Responses return only
to the initiator that owns the transaction.

## Interrupts

The integrated interrupt sources are:

| Bit | Source |
| --- | --- |
| 0 | DMA completion when the DMA-local enable is set |
| 1 | command processor completion |
| 2 | vector, reduction, or GEMM completion |
| 3 | DMA, command, accelerator, or memory-fabric error |
| 4 | timer expiration |

The interrupt controller keeps sources pending until firmware writes the corresponding
bit to `IRQ_STATUS`. Global source masking uses `IRQ_ENABLE`.

## Performance Events

The performance block receives DMA active and stalled cycles, aggregate accelerator
active and stalled cycles, command completion, queue occupancy, DMA byte counts,
interrupt service latency, and scheduler stalls. Counter reads use the register block's
low-word snapshot protocol.

## End-to-End Verification

The SoC Verilator harness accesses only top-level interfaces. It:

1. Verifies reset, identity registers, and illegal MMIO behavior.
2. Copies an odd byte count from external memory to scratchpad and back through MMIO DMA.
3. Submits a queued DMA descriptor.
4. Loads vector inputs with DMA, executes vector add, and copies results back.
5. Loads a signed reduction input, executes sum, and copies the result back.
6. Loads rectangular matrices, executes GEMM, and copies the result back.
7. Checks DMA, command, accelerator, and timer interrupts.
8. Reads total-cycle, byte, completion, and queue high-water counters.

External-memory request stalls and response latency vary with seeds `1`, `7`, `19`, and
`41`. Accelerator outputs are compared with independent C++ reference models.
