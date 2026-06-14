# Known Limitations

- The implemented RTL currently covers shared definitions, interfaces, flow-control
  primitives, RAM, scratchpad storage, the AXI-Lite register block, and DMA. Remaining
  SoC services and accelerators follow the milestone order recorded in `project_plan.md`.
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
- Default scratchpad and external-memory capacities are intentionally bounded for
  regression speed.
- Accelerator arithmetic is fixed width. Overflow and output conversion are architectural
  behaviors that must be selected explicitly and verified.
- Commercial-simulator UVM results remain not run until a compatible licensed simulator
  is available.
- Optional synthesis estimates are comparative and do not establish a fabrication-ready
  implementation.
