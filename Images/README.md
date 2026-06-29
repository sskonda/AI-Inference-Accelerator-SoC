# Simulation Artifacts

This directory contains real simulation artifacts generated from the local
AI-Inference-Accelerator-SoC RTL.

## What Was Run

- Full RTL compile: `Images/logs/xsim_compile.log`
- Primitive directed simulation: FIFO edge cases, skid buffer stall/hold, RAM
  byte enables/read-first collision, scratchpad bounds and alignment checks
- DMA directed simulation: normal copy, partial final write strobe,
  backpressure stalls, zero-length no-op, illegal address, busy rejection,
  source/destination response errors, and reset while active
- Services directed simulation: one-shot and periodic timer expiration,
  interrupt pending/clear latency, performance-counter increments, high-water
  tracking, and counter clear
- Command directed simulation: DMA dispatch, invalid opcode response,
  vector backpressure stall, priority-first dispatch, and full queue rejection
- Vector directed simulation: add, scale, partial final strobe, backpressure,
  invalid command, and memory response error
- Reduction directed simulation: sum, max, backpressure, invalid opcode,
  read response error, and write response error
- GEMM directed simulation: 2x2 matrix multiply, backpressure, invalid
  dimensions, read response error, and write response error

## Where To Look

- `Images/waveforms/*.png`: Vivado-style waveform screenshots rendered from
  real per-cycle traces
- `Images/terminal/*.png`: Ubuntu-terminal-style screenshots rendered from
  real terminal log files
- `Images/logs/*.log`: raw Vivado XSim compile, elaboration, and simulator terminal output
- `Images/waves/*.wdb`: Vivado waveform databases
- `Images/vcd/*.vcd`: raw VCD waveform dumps
- `Images/traces/*.csv`: selected signal traces used to render the PNGs
- `Images/generated_tb/*.sv`: generated directed testbenches used only for
  artifact capture
- `Images/scripts/Render-Artifacts.ps1`: renderer for the PNG screenshots

## Environment Note

Vivado Simulator v2024.2.0 was run locally through `xvlog`, `xelab`, and
`xsim`. The PNGs are presentation renderings of real XSim logs and per-cycle
traces in Ubuntu 24.04/Vivado-style visuals. The repository's native Verilator
`TRACE=1` flow could not be used here because Verilator and GTKWave were not
available on `PATH`.
