#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD_DIRECTORY = ROOT / "build" / "verilator"
RESULT_DIRECTORY = ROOT / "perf" / "results"
CSV_PATH = RESULT_DIRECTORY / "baseline_metrics.csv"
JSON_PATH = RESULT_DIRECTORY / "baseline_metrics.json"
CONFIG_NAME = "baseline"

SIMULATORS = (
    ("soc", BUILD_DIRECTORY / "Vsoc_top"),
    ("dma", BUILD_DIRECTORY / "Vdma_test_top"),
    ("vector", BUILD_DIRECTORY / "Vvector_test_top"),
    ("reduction", BUILD_DIRECTORY / "Vreduction_test_top"),
    ("gemm", BUILD_DIRECTORY / "Vgemm_test_top"),
)

CSV_FIELDS = (
    "source_revision",
    "source_dirty",
    "config",
    "suite",
    "workload",
    "seed",
    "length_bytes",
    "elements",
    "rows",
    "columns",
    "inner",
    "outputs",
    "total_cycles",
    "cycles",
    "active_cycles",
    "stalled_cycles",
    "dma_active_cycles",
    "dma_stalled_cycles",
    "accelerator_active_cycles",
    "accelerator_stalled_cycles",
    "queue_high_water",
    "commands_completed",
    "bytes_read",
    "bytes_written",
    "interrupt_latency",
    "scheduler_stalls",
    "reads",
    "writes",
    "source_requests",
    "destination_requests",
    "completed_elements",
    "final_writes",
    "dma_done_events",
    "command_done_events",
    "accelerator_done_events",
    "irq_seen",
    "bytes_per_cycle",
    "elements_per_cycle",
    "outputs_per_cycle",
    "local_stall_percent",
    "dma_stall_percent",
    "accelerator_stall_percent",
    "accelerator_utilization_percent",
)


def git_output(*args: str) -> str:
    return subprocess.check_output(("git", *args), cwd=ROOT, text=True).strip()


def git_dirty() -> bool:
    return bool(git_output("status", "--porcelain"))


def require_simulators() -> None:
    missing = [path.relative_to(ROOT) for _, path in SIMULATORS if not path.is_file()]
    if missing:
        formatted = ", ".join(str(path) for path in missing)
        raise RuntimeError(
            f"missing Verilator executable: {formatted}; run make verilator-build"
        )


def parse_perf_line(line: str) -> dict[str, str] | None:
    if not line.startswith("PERF "):
        return None
    record: dict[str, str] = {}
    for token in line.split()[1:]:
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        record[key] = value
    return record


def integer(record: dict[str, str], key: str) -> int:
    value = record.get(key, "")
    if value == "":
        return 0
    return int(value, 0)


def ratio(numerator: int, denominator: int) -> str:
    if denominator == 0:
        return ""
    return f"{numerator / denominator:.4f}"


def percent(numerator: int, denominator: int) -> str:
    if denominator == 0:
        return ""
    return f"{(100.0 * numerator) / denominator:.2f}"


def enrich_record(record: dict[str, str]) -> dict[str, str]:
    cycles = integer(record, "cycles")
    total_cycles = integer(record, "total_cycles")
    active_cycles = integer(record, "active_cycles")
    stalled_cycles = integer(record, "stalled_cycles")
    dma_active = integer(record, "dma_active_cycles")
    dma_stalled = integer(record, "dma_stalled_cycles")
    accelerator_active = integer(record, "accelerator_active_cycles")
    accelerator_stalled = integer(record, "accelerator_stalled_cycles")
    bytes_written = integer(record, "bytes_written")
    bytes_read = integer(record, "bytes_read")
    elements = integer(record, "elements")
    outputs = integer(record, "outputs")

    if bytes_written:
        record["bytes_per_cycle"] = ratio(bytes_written, cycles or total_cycles)
    elif bytes_read:
        record["bytes_per_cycle"] = ratio(bytes_read, cycles or total_cycles)
    if elements:
        record["elements_per_cycle"] = ratio(elements, cycles)
    if outputs:
        record["outputs_per_cycle"] = ratio(outputs, cycles)
    if active_cycles or stalled_cycles:
        record["local_stall_percent"] = percent(
            stalled_cycles, active_cycles + stalled_cycles
        )
    if dma_active or dma_stalled:
        record["dma_stall_percent"] = percent(dma_stalled, dma_active + dma_stalled)
    if accelerator_active or accelerator_stalled:
        record["accelerator_stall_percent"] = percent(
            accelerator_stalled, accelerator_active + accelerator_stalled
        )
    if total_cycles:
        record["accelerator_utilization_percent"] = percent(
            accelerator_active, total_cycles
        )
    return record


def run_simulator(name: str, path: Path, seed: int) -> list[dict[str, str]]:
    command = (str(path), "--test", "perf", "--seed", str(seed))
    result = subprocess.run(
        command,
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    sys.stdout.write(result.stdout)
    if result.returncode != 0:
        raise RuntimeError(f"{name} performance run failed")
    records = []
    for line in result.stdout.splitlines():
        record = parse_perf_line(line)
        if record is not None:
            records.append(enrich_record(record))
    if not records:
        raise RuntimeError(f"{name} performance run did not emit PERF records")
    return records


def write_results(records: list[dict[str, str]]) -> None:
    RESULT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    with CSV_PATH.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=CSV_FIELDS)
        writer.writeheader()
        for record in records:
            writer.writerow({field: record.get(field, "") for field in CSV_FIELDS})
    JSON_PATH.write_text(
        json.dumps(records, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Capture deterministic baseline performance metrics"
    )
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()

    try:
        require_simulators()
        revision = git_output("rev-parse", "--short", "HEAD")
        dirty = "true" if git_dirty() else "false"
        records: list[dict[str, str]] = []
        for name, path in SIMULATORS:
            for record in run_simulator(name, path, args.seed):
                record["source_revision"] = revision
                record["source_dirty"] = dirty
                record["config"] = CONFIG_NAME
                records.append(record)
        write_results(records)
    except (RuntimeError, subprocess.CalledProcessError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"Performance baseline written to {CSV_PATH.relative_to(ROOT)}")
    print(f"Performance baseline written to {JSON_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
