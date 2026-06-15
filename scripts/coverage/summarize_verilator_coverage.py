#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
from collections import defaultdict
from pathlib import Path


COVERAGE_PATTERN = re.compile(r"^C '(?P<key>.*)' (?P<count>[0-9]+)$")
FIELD_SEPARATOR = "\x01"
VALUE_SEPARATOR = "\x02"


def field_value(key: str, field_name: str) -> str:
    prefix = f"{field_name}{VALUE_SEPARATOR}"
    for field in key.split(FIELD_SEPARATOR):
        if field.startswith(prefix):
            return field[len(prefix):]
    return "unknown"


def parse_database(path: Path) -> dict[str, int]:
    points: dict[str, int] = defaultdict(int)
    with path.open("r", encoding="utf-8", errors="replace") as database:
        for raw_line in database:
            line = raw_line.rstrip("\n")
            match = COVERAGE_PATTERN.match(line)
            if match is None:
                continue
            points[match.group("key")] += int(match.group("count"))
    return points


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize Verilator coverage data")
    parser.add_argument("databases", nargs="+", type=Path)
    parser.add_argument("--reporter-status", default="not requested")
    args = parser.parse_args()

    merged_points: dict[str, int] = defaultdict(int)
    database_count = 0
    total_bytes = 0

    for database_path in args.databases:
        if not database_path.is_file():
            raise FileNotFoundError(database_path)
        database_count += 1
        total_bytes += database_path.stat().st_size
        for key, count in parse_database(database_path).items():
            merged_points[key] += count

    covered_points = sum(1 for count in merged_points.values() if count > 0)
    total_points = len(merged_points)
    uncovered_points = total_points - covered_points
    coverage_percent = (covered_points * 100.0 / total_points) if total_points else 0.0

    page_totals: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    file_totals: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for key, count in merged_points.items():
        page = field_value(key, "page")
        source_file = field_value(key, "f")
        page_totals[page][0] += 1
        file_totals[source_file][0] += 1
        if count > 0:
            page_totals[page][1] += 1
            file_totals[source_file][1] += 1

    print("# Verilator Coverage Summary")
    print()
    print(f"Reporter status: {args.reporter_status}")
    print(f"Databases: {database_count}")
    print(f"Database bytes: {total_bytes}")
    print(f"Unique points: {total_points}")
    print(f"Covered points: {covered_points}")
    print(f"Uncovered points: {uncovered_points}")
    print(f"Point coverage: {coverage_percent:.2f}%")
    print()
    print("## Coverage By Page")
    print()
    print("| Page | Covered | Total | Percent |")
    print("| --- | ---: | ---: | ---: |")
    for page, (total, covered) in sorted(page_totals.items()):
        percent = (covered * 100.0 / total) if total else 0.0
        print(f"| `{page}` | {covered} | {total} | {percent:.2f}% |")
    print()
    print("## Coverage By Source File")
    print()
    print("| Source | Covered | Total | Percent |")
    print("| --- | ---: | ---: | ---: |")
    for source_file, (total, covered) in sorted(file_totals.items()):
        percent = (covered * 100.0 / total) if total else 0.0
        print(f"| `{source_file}` | {covered} | {total} | {percent:.2f}% |")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
