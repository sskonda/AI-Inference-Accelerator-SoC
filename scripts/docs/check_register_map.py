#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PACKAGE_PATH = ROOT / "rtl" / "packages" / "reg_pkg.sv"
SOC_PACKAGE_PATH = ROOT / "rtl" / "packages" / "soc_pkg.sv"
ACCEL_PACKAGE_PATH = ROOT / "rtl" / "packages" / "accel_pkg.sv"
DOCUMENT_PATH = ROOT / "docs" / "register_map.md"
CPP_HEADER_PATH = ROOT / "firmware" / "include" / "soc_registers.hpp"

PACKAGE_REGISTER = re.compile(
    r"localparam\s+reg_offset_t\s+REG_([A-Z0-9_]+)\s*=\s*12'h([0-9a-fA-F]+);"
)
DOCUMENT_REGISTER = re.compile(
    r"^\|\s*`0x([0-9a-fA-F]+)`\s*\|\s*`([A-Z0-9_]+)`\s*\|",
    re.MULTILINE,
)
CPP_REGISTER = re.compile(
    r"inline constexpr std::uint32_t REG_([A-Z0-9_]+) = 0x([0-9a-fA-F]+)U;"
)
SV_ERROR = re.compile(r"ERR_([A-Z0-9_]+)\s*=\s*4'h([0-9a-fA-F])")
CPP_ERROR = re.compile(r"inline constexpr std::uint32_t ERR_([A-Z0-9_]+) = ([0-9]+)U;")
SV_OPCODE = re.compile(r"CMD_OP_([A-Z0-9_]+)\s*=\s*4'h([0-9a-fA-F])")
CPP_OPCODE = re.compile(
    r"inline constexpr std::uint32_t CMD_OP_([A-Z0-9_]+) = ([0-9]+)U;"
)
SV_PERF_COUNTER = re.compile(r"PERF_([A-Z0-9_]+)\s*=\s*4'h([0-9a-fA-F])")
CPP_PERF_COUNTER = re.compile(
    r"inline constexpr std::uint32_t PERF_([A-Z0-9_]+) = ([0-9]+)U;"
)
SV_IRQ_BIT = re.compile(
    r"localparam\s+int\s+unsigned\s+IRQ_([A-Z0-9_]+)_BIT\s*=\s*([0-9]+);"
)
CPP_IRQ_BIT = re.compile(
    r"inline constexpr unsigned IRQ_([A-Z0-9_]+)_BIT = ([0-9]+)U;"
)
SV_SCHEDULER_POLICY = re.compile(r"SCHED_([A-Z0-9_]+)\s*=\s*2'b([01]+)")
CPP_SCHEDULER_POLICY = re.compile(
    r"inline constexpr std::uint32_t SCHED_([A-Z0-9_]+) = ([0-9]+)U;"
)
SV_EXECUTOR_TARGET = re.compile(r"EXEC_TARGET_([A-Z0-9_]+)\s*=\s*3'd([0-9]+)")
CPP_EXECUTOR_TARGET = re.compile(
    r"inline constexpr std::uint32_t EXEC_TARGET_([A-Z0-9_]+) = ([0-9]+)U;"
)


def package_map() -> dict[str, int]:
    text = PACKAGE_PATH.read_text(encoding="utf-8")
    return {name: int(offset, 16) for name, offset in PACKAGE_REGISTER.findall(text)}


def document_map() -> dict[str, int]:
    text = DOCUMENT_PATH.read_text(encoding="utf-8")
    return {name: int(offset, 16) for offset, name in DOCUMENT_REGISTER.findall(text)}


def cpp_map() -> dict[str, int]:
    text = CPP_HEADER_PATH.read_text(encoding="utf-8")
    return {name: int(offset, 16) for name, offset in CPP_REGISTER.findall(text)}


def enum_map(path: Path, pattern: re.Pattern[str], base: int) -> dict[str, int]:
    text = path.read_text(encoding="utf-8")
    return {name: int(value, base) for name, value in pattern.findall(text)}


def compare_maps(
    label: str, rtl_values: dict[str, int], cpp_values: dict[str, int]
) -> list[str]:
    failures: list[str] = []
    for name in sorted(rtl_values.keys() - cpp_values.keys()):
        failures.append(f"{label} missing from C++ header: {name}")
    for name in sorted(cpp_values.keys() - rtl_values.keys()):
        failures.append(f"C++ {label} missing from RTL package: {name}")
    for name in sorted(rtl_values.keys() & cpp_values.keys()):
        if rtl_values[name] != cpp_values[name]:
            failures.append(
                f"{label} mismatch for {name}: "
                f"RTL={rtl_values[name]}, C++={cpp_values[name]}"
            )
    return failures


def main() -> int:
    rtl_registers = package_map()
    documented_registers = document_map()
    cpp_registers = cpp_map()
    rtl_errors = enum_map(SOC_PACKAGE_PATH, SV_ERROR, 16)
    cpp_errors = enum_map(CPP_HEADER_PATH, CPP_ERROR, 10)
    rtl_opcodes = enum_map(ACCEL_PACKAGE_PATH, SV_OPCODE, 16)
    cpp_opcodes = enum_map(CPP_HEADER_PATH, CPP_OPCODE, 10)
    rtl_perf_counters = enum_map(SOC_PACKAGE_PATH, SV_PERF_COUNTER, 16)
    cpp_perf_counters = enum_map(CPP_HEADER_PATH, CPP_PERF_COUNTER, 10)
    rtl_irq_bits = enum_map(SOC_PACKAGE_PATH, SV_IRQ_BIT, 10)
    cpp_irq_bits = enum_map(CPP_HEADER_PATH, CPP_IRQ_BIT, 10)
    rtl_scheduler_policies = enum_map(ACCEL_PACKAGE_PATH, SV_SCHEDULER_POLICY, 2)
    cpp_scheduler_policies = enum_map(CPP_HEADER_PATH, CPP_SCHEDULER_POLICY, 10)
    rtl_executor_targets = enum_map(ACCEL_PACKAGE_PATH, SV_EXECUTOR_TARGET, 10)
    cpp_executor_targets = enum_map(CPP_HEADER_PATH, CPP_EXECUTOR_TARGET, 10)
    failures: list[str] = []

    if not rtl_registers:
        failures.append("no register constants found in reg_pkg.sv")
    if not documented_registers:
        failures.append("no register rows found in register_map.md")

    for name in sorted(rtl_registers.keys() - documented_registers.keys()):
        failures.append(f"register missing from documentation: {name}")
    for name in sorted(documented_registers.keys() - rtl_registers.keys()):
        failures.append(f"documented register missing from RTL package: {name}")
    for name in sorted(rtl_registers.keys() & documented_registers.keys()):
        if rtl_registers[name] != documented_registers[name]:
            failures.append(
                f"offset mismatch for {name}: "
                f"RTL=0x{rtl_registers[name]:03x}, docs=0x{documented_registers[name]:03x}"
            )

    failures.extend(compare_maps("register", rtl_registers, cpp_registers))
    failures.extend(compare_maps("error code", rtl_errors, cpp_errors))
    failures.extend(compare_maps("command opcode", rtl_opcodes, cpp_opcodes))
    failures.extend(
        compare_maps("performance counter", rtl_perf_counters, cpp_perf_counters)
    )
    failures.extend(compare_maps("interrupt bit", rtl_irq_bits, cpp_irq_bits))
    failures.extend(
        compare_maps(
            "scheduler policy", rtl_scheduler_policies, cpp_scheduler_policies
        )
    )
    failures.extend(
        compare_maps("executor target", rtl_executor_targets, cpp_executor_targets)
    )

    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1

    print(
        "Register/protocol definition check: PASS "
        f"({len(rtl_registers)} registers, {len(rtl_errors)} errors, "
        f"{len(rtl_opcodes)} opcodes, {len(rtl_perf_counters)} counters, "
        f"{len(rtl_irq_bits)} interrupt bits, "
        f"{len(rtl_scheduler_policies)} scheduler policies, "
        f"{len(rtl_executor_targets)} executor targets)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
