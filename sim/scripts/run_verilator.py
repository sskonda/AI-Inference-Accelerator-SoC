#!/usr/bin/env python3

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SIMULATOR = ROOT / "build" / "verilator" / "Vsoc_top"


def require_simulator() -> None:
    if not SIMULATOR.is_file():
        raise RuntimeError("simulator executable is missing; run make verilator-build")


def run_case(case_name: str, seed: int, coverage: bool = False) -> None:
    require_simulator()
    command = [str(SIMULATOR), "--test", case_name, "--seed", str(seed)]
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
            for seed in parse_seeds(args.seeds):
                run_case("regress", seed, coverage=args.suite == "coverage")
    except (RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"Verilator {args.suite}: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
