# Firmware Organization

The firmware layer is portable C++17 organized as embedded software:

- `include/` contains register definitions, public driver APIs, task types, and workload
  descriptors.
- `drivers/` contains MMIO, DMA, accelerator, timer, and interrupt drivers.
- `rtos/` contains the cooperative scheduler and ISR dispatch model.
- `workloads/` contains task entry points and workload construction.
- `tests/` contains host-side unit tests independent of RTL.

Firmware accesses hardware only through the MMIO abstraction. The Verilator harness
provides the concrete implementation and advances simulation time.

The public architecture and task lifecycle are documented in
[`docs/firmware.md`](../docs/firmware.md). Run `make firmware-test` for host-side driver
and scheduler tests.
