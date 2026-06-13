#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PACKAGE_PATH = ROOT / "rtl" / "packages" / "reg_pkg.sv"
DOCUMENT_PATH = ROOT / "docs" / "register_map.md"

PACKAGE_REGISTER = re.compile(
    r"localparam\s+reg_offset_t\s+REG_([A-Z0-9_]+)\s*=\s*12'h([0-9a-fA-F]+);"
)
DOCUMENT_REGISTER = re.compile(
    r"^\|\s*`0x([0-9a-fA-F]+)`\s*\|\s*`([A-Z0-9_]+)`\s*\|",
    re.MULTILINE,
)


def package_map() -> dict[str, int]:
    text = PACKAGE_PATH.read_text(encoding="utf-8")
    return {name: int(offset, 16) for name, offset in PACKAGE_REGISTER.findall(text)}


def document_map() -> dict[str, int]:
    text = DOCUMENT_PATH.read_text(encoding="utf-8")
    return {name: int(offset, 16) for offset, name in DOCUMENT_REGISTER.findall(text)}


def main() -> int:
    rtl_registers = package_map()
    documented_registers = document_map()
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

    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1

    print(f"Register map check: PASS ({len(rtl_registers)} registers)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
