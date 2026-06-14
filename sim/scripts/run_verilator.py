#!/usr/bin/env python3

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
COVERAGE_DATABASE = ROOT / "coverage" / "coverage.dat"
SIMULATOR_CANDIDATES = (
    ROOT / "build" / "verilator" / "Vsoc_top",
    ROOT / "build" / "verilator" / "Vprimitive_test_top",
)


def simulator_path() -> Path:
    for candidate in SIMULATOR_CANDIDATES:
        if candidate.is_file():
            return candidate
    raise RuntimeError("simulator executable is missing; run make verilator-build")


def run_case(case_name: str, seed: int, coverage: bool = False) -> None:
    simulator = simulator_path()
    command = [str(simulator), "--test", case_name, "--seed", str(seed)]
    if coverage:
        command.append("--coverage")
    subprocess.run(command, cwd=ROOT, check=True)


def parse_seeds(raw_seeds: str) -> list[int]:
    seeds = [int(value) for value in raw_seeds.split()]
    if not seeds:
        raise ValueError("at least one seed is required")
    return seeds


def main() -> int:
    parser = argparse.ArgumentParser(description="Run deterministic Verilator suites")
    parser.add_argument("suite", choices=("smoke", "regress", "coverage"))
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--seeds", default="1 7 19 41")
    args = parser.parse_args()

    if shutil.which("verilator") is None:
        print("error: required tool not found: verilator", file=sys.stderr)
        return 2

    try:
        if args.suite == "smoke":
            run_case("smoke", args.seed)
        else:
            if args.suite == "coverage" and COVERAGE_DATABASE.exists():
                COVERAGE_DATABASE.unlink()
            for seed in parse_seeds(args.seeds):
                run_case("regress", seed, coverage=args.suite == "coverage")
            if args.suite == "coverage" and (
                not COVERAGE_DATABASE.is_file() or COVERAGE_DATABASE.stat().st_size == 0
            ):
                raise RuntimeError(
                    "coverage database was not produced; build an instrumented simulator"
                )
    except (RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"Verilator {args.suite}: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
