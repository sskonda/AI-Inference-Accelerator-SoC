# Known Limitations

- The repository currently contains architecture and build contracts; implementation and
  verification are added in the milestone order recorded in `project_plan.md`.
- The local environment does not currently provide Verible, Verilator, a UVM-capable
  simulator, or Yosys. Targets report those absences and do not claim a pass.
- The platform is simulation-only and does not include board support, implementation
  constraints, timing closure, or physical area results.
- Firmware is a C++ control-core model. No instruction-set processor is present.
- The AXI-Lite interface is a documented single-beat subset and does not support bursts.
- The baseline external memory model permits one request in flight and is not a detailed
  DRAM timing model.
- Default scratchpad and external-memory capacities are intentionally bounded for
  regression speed.
- Accelerator arithmetic is fixed width. Overflow and output conversion are architectural
  behaviors that must be selected explicitly and verified.
- Commercial-simulator UVM results remain not run until a compatible licensed simulator
  is available.
- Optional synthesis estimates are comparative and do not establish a fabrication-ready
  implementation.
