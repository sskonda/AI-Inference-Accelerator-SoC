#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


METRIC_PATTERNS = {
    "wires": re.compile(r"^\s*(\d+)\s+wires\s*$"),
    "wire_bits": re.compile(r"^\s*(\d+)\s+wire bits\s*$"),
    "public_wires": re.compile(r"^\s*(\d+)\s+public wires\s*$"),
    "public_wire_bits": re.compile(r"^\s*(\d+)\s+public wire bits\s*$"),
    "ports": re.compile(r"^\s*(\d+)\s+ports\s*$"),
    "port_bits": re.compile(r"^\s*(\d+)\s+port bits\s*$"),
    "memories": re.compile(r"^\s*(\d+)\s+memories\s*$"),
    "memory_bits": re.compile(r"^\s*(\d+)\s+memory bits\s*$"),
    "cells": re.compile(r"^\s*(\d+)\s+cells\s*$"),
}
CELL_PATTERN = re.compile(r"^\s*(\d+)\s+(\$[A-Za-z0-9_]+)\s*$")
VERSION_PATTERN = re.compile(r"^\s*(Yosys .*)$")


def parse_stat(log_text: str, top: str) -> dict[str, object]:
    metrics: dict[str, int] = {}
    cells: dict[str, int] = {}
    yosys_version = "unknown"
    in_top = False

    for line in log_text.splitlines():
        version_match = VERSION_PATTERN.match(line)
        if version_match is not None:
            yosys_version = version_match.group(1)

        if line.strip() == f"=== {top} ===":
            in_top = True
            continue
        if in_top and line.startswith("End of script."):
            break
        if not in_top:
            continue

        for metric, pattern in METRIC_PATTERNS.items():
            match = pattern.match(line)
            if match is not None:
                metrics[metric] = int(match.group(1))
                break
        else:
            cell_match = CELL_PATTERN.match(line)
            if cell_match is not None:
                cells[cell_match.group(2)] = int(cell_match.group(1))

    missing_metrics = sorted(set(METRIC_PATTERNS) - set(metrics))
    if missing_metrics:
        formatted = ", ".join(missing_metrics)
        raise RuntimeError(f"Yosys stat report is missing metrics: {formatted}")

    return {
        "top": top,
        "flow": "yosys-slang-structural-stat",
        "yosys_version": yosys_version,
        "scope": [
            "SystemVerilog read through the Yosys slang frontend",
            "Assertions ignored for synthesis estimation",
            "Initial validation blocks ignored for synthesis estimation",
            "Technology mapping and physical timing are not included",
        ],
        "metrics": metrics,
        "cells": dict(sorted(cells.items())),
    }


def markdown_table(rows: list[tuple[str, object]]) -> str:
    output = ["| Metric | Value |", "| --- | ---: |"]
    for name, value in rows:
        output.append(f"| {name} | {value} |")
    return "\n".join(output)


def write_markdown(summary: dict[str, object], path: Path) -> None:
    metrics = summary["metrics"]
    assert isinstance(metrics, dict)
    cells = summary["cells"]
    assert isinstance(cells, dict)

    metric_rows = [
        ("Wires", metrics["wires"]),
        ("Wire bits", metrics["wire_bits"]),
        ("Ports", metrics["ports"]),
        ("Port bits", metrics["port_bits"]),
        ("Memories", metrics["memories"]),
        ("Memory bits", metrics["memory_bits"]),
        ("Cells", metrics["cells"]),
    ]
    cell_rows = [(cell_type, count) for cell_type, count in cells.items()]

    text = [
        f"# Yosys Estimate: `{summary['top']}`",
        "",
        f"Flow: `{summary['flow']}`",
        "",
        f"Tool: `{summary['yosys_version']}`",
        "",
        "## Scope",
        "",
    ]
    for item in summary["scope"]:
        text.append(f"- {item}")
    text.extend(
        [
            "",
            "## Structural Metrics",
            "",
            markdown_table(metric_rows),
            "",
            "## Generic Cell Counts",
            "",
            markdown_table(cell_rows),
            "",
        ]
    )
    path.write_text("\n".join(text) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize a Yosys stat report")
    parser.add_argument("--top", required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--markdown", type=Path, required=True)
    args = parser.parse_args()

    summary = parse_stat(args.log.read_text(encoding="utf-8"), args.top)
    args.json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(summary, args.markdown)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
