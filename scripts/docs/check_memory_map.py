#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PACKAGE_PATH = ROOT / "rtl" / "packages" / "soc_pkg.sv"
CPP_HEADER_PATH = ROOT / "firmware" / "include" / "soc_memory_map.hpp"

SV_INTEGER = re.compile(
    r"localparam\s+int\s+unsigned\s+([A-Z0-9_]+)\s*=\s*([0-9]+);"
)
SV_HEX = re.compile(
    r"localparam\s+logic\s+\[ADDR_WIDTH-1:0\]\s+([A-Z0-9_]+)\s*="
    r"\s*32'h([0-9a-fA-F_]+);"
)
CPP_INTEGER = re.compile(
    r"inline constexpr (?:std::uint32_t|std::size_t|unsigned)\s+"
    r"([A-Z0-9_]+)\s*=\s*(?:0x([0-9a-fA-F]+)|([0-9]+))U;"
)


def systemverilog_values() -> dict[str, int]:
    text = PACKAGE_PATH.read_text(encoding="utf-8")
    values = {name: int(value) for name, value in SV_INTEGER.findall(text)}
    values.update(
        {name: int(value.replace("_", ""), 16) for name, value in SV_HEX.findall(text)}
    )
    values["DATA_BYTES"] = values["DATA_WIDTH"] // values["BITS_PER_BYTE"]
    values["SPM_SIZE_BYTES"] = values["SPM_SIZE_KIB"] * values["BYTES_PER_KIB"]
    values["DRAM_SIZE_BYTES"] = values["DRAM_SIZE_KIB"] * values["BYTES_PER_KIB"]
    return values


def cpp_values() -> dict[str, int]:
    text = CPP_HEADER_PATH.read_text(encoding="utf-8")
    values: dict[str, int] = {}
    for name, hex_value, decimal_value in CPP_INTEGER.findall(text):
        values[name] = int(hex_value, 16) if hex_value else int(decimal_value)
    return values


def main() -> int:
    rtl = systemverilog_values()
    cpp = cpp_values()
    compared_names = (
        "DATA_BYTES",
        "SPM_BASE_ADDR",
        "SPM_SIZE_BYTES",
        "DRAM_BASE_ADDR",
        "DRAM_SIZE_BYTES",
        "DEFAULT_DMA_BURST_BEATS",
    )
    failures: list[str] = []

    for name in compared_names:
        if name not in cpp:
            failures.append(f"memory-map constant missing from C++ header: {name}")
        elif rtl[name] != cpp[name]:
            failures.append(
                f"memory-map mismatch for {name}: RTL={rtl[name]}, C++={cpp[name]}"
            )

    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1

    print(f"Memory map check: PASS ({len(compared_names)} constants)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
