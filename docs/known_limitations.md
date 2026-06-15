# Known Limitations

- The implemented RTL currently covers shared definitions, interfaces, flow-control
  primitives, RAM, scratchpad storage, the AXI-Lite register block, DMA, timer,
  interrupts, performance counters, the command queue, and the command processor. The
  vector, reduction, and tiled matrix accelerators are also implemented. Full SoC
  integration follows the milestone order recorded in `project_plan.md`.
- The local environment provides user-local Verible and Verilator installations. It does
  not currently provide a UVM-capable simulator or Yosys. Targets report those absences
  and do not claim a pass.
- The platform is simulation-only and does not include board support, implementation
  constraints, timing closure, or physical area results.
- Firmware is a C++ control-core model. No instruction-set processor is present.
- The AXI-Lite interface is a documented single-beat subset and does not support bursts.
- The current AXI-Lite agent is a reusable component skeleton. Full sequences, scoreboards,
  coverage, and simulator compilation are added with the complete UVM environment.
- The baseline external memory model permits one request in flight and is not a detailed
  DRAM timing model.
- DMA uses one buffered word and ordered responses. Its logical bursts do not create
  multiple outstanding memory requests, and overlapping copies are not guaranteed.
- The baseline command processor permits one accelerator command in flight. This gives
  deterministic completion ordering but does not yet overlap independent accelerators.
- The vector accelerator uses one memory port and serializes source reads and destination
  writes. Packed lanes provide word-level parallelism, but source and destination memory
  operations do not overlap in the baseline.
- The reduction accelerator parallelizes lanes within one memory word but processes
  memory words sequentially through one accumulator and one memory port.
- The matrix accelerator computes one output tile at a time and serializes scratchpad
  requests through one memory port. Tile multiply-accumulates are parallel, but source
  reads and output writes do not overlap.
- Default scratchpad and external-memory capacities are intentionally bounded for
  regression speed.
- Accelerator arithmetic is fixed width. Overflow and output conversion are architectural
  behaviors that must be selected explicitly and verified.
- Commercial-simulator UVM results remain not run until a compatible licensed simulator
  is available.
- Optional synthesis estimates are comparative and do not establish a fabrication-ready
  implementation.
