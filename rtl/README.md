# RTL Organization

Synthesizable sources are grouped by ownership:

- `packages/` defines architectural constants, types, opcodes, errors, and register
  offsets before dependent files are compiled.
- `interfaces/` defines AXI-Lite, memory, stream, command, and interrupt protocols.
- `common/`, `fifo/`, and `memory/` contain reusable primitives.
- `bus/` and `regs/` own control-plane routing and architectural state.
- `dma/`, `command_queue/`, `irq/`, `timer/`, and `perf/` own SoC services.
- `accel/` contains vector, reduction, and matrix engines.
- `soc/` contains integration and no reusable leaf logic.

`rtl/files.f` is introduced with the shared packages and remains the ordered source of
truth for Verilator and UVM compilation.
