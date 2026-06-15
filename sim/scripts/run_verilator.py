#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
COVERAGE_DATABASE = ROOT / "coverage" / "coverage.dat"
COVERAGE_DIRECTORY = ROOT / "coverage" / "verilator"
BUILD_DIRECTORY = Path(
    os.environ.get("VERILATOR_BUILD_DIR", str(ROOT / "build" / "verilator"))
)
if not BUILD_DIRECTORY.is_absolute():
    BUILD_DIRECTORY = ROOT / BUILD_DIRECTORY
LOG_DIRECTORY = ROOT / "logs" / "verilator"
TRACE_DIRECTORY = LOG_DIRECTORY / "traces"

INITIALIZATION_MODES = {
    "zero": 0,
    "ones": 1,
    "random": 2,
}


@dataclass(frozen=True)
class Simulator:
    name: str
    path: Path
    supports_initialization_modes: bool = False
    supports_trace: bool = False


SIMULATOR_CANDIDATES = (
    Simulator(
        "soc",
        BUILD_DIRECTORY / "Vsoc_top",
        supports_initialization_modes=True,
        supports_trace=True,
    ),
    Simulator("gemm", BUILD_DIRECTORY / "Vgemm_test_top"),
    Simulator("reduction", BUILD_DIRECTORY / "Vreduction_test_top"),
    Simulator("vector", BUILD_DIRECTORY / "Vvector_test_top"),
    Simulator("command", BUILD_DIRECTORY / "Vcommand_test_top"),
    Simulator("services", BUILD_DIRECTORY / "Vservices_test_top"),
    Simulator("dma", BUILD_DIRECTORY / "Vdma_test_top"),
    Simulator("register", BUILD_DIRECTORY / "Vregister_test_top"),
    Simulator("primitive", BUILD_DIRECTORY / "Vprimitive_test_top"),
)


def simulators() -> tuple[Simulator, ...]:
    missing = tuple(candidate.path for candidate in SIMULATOR_CANDIDATES if not candidate.path.is_file())
    if missing:
        formatted = ", ".join(str(path.relative_to(ROOT)) for path in missing)
        raise RuntimeError(f"simulator executable is missing: {formatted}; run make verilator-build")
    return SIMULATOR_CANDIDATES


def parse_words(raw_values: str, description: str) -> list[str]:
    values = raw_values.split()
    if not values:
        raise ValueError(f"at least one {description} is required")
    return values


def parse_seeds(raw_seeds: str) -> list[int]:
    return [int(value) for value in parse_words(raw_seeds, "seed")]


def parse_initialization_modes(raw_modes: str) -> list[str]:
    modes = parse_words(raw_modes, "initialization mode")
    invalid = [mode for mode in modes if mode not in INITIALIZATION_MODES]
    if invalid:
        choices = ", ".join(INITIALIZATION_MODES)
        raise ValueError(f"unsupported initialization mode {invalid[0]!r}; choose from {choices}")
    return modes


def run_simulator(
    simulator: Simulator,
    case_name: str,
    seed: int,
    initialization_mode: str,
    coverage: bool,
    trace: bool,
) -> None:
    LOG_DIRECTORY.mkdir(parents=True, exist_ok=True)
    log_file = LOG_DIRECTORY / (
        f"{simulator.name}_{case_name}_seed{seed}_{initialization_mode}.log"
    )
    command = [str(simulator.path), "--test", case_name, "--seed", str(seed)]

    if simulator.supports_initialization_modes:
        reset_mode = INITIALIZATION_MODES[initialization_mode]
        command.extend(
            (
                f"+verilator+rand+reset+{reset_mode}",
                f"+verilator+seed+{seed}",
            )
        )
    if coverage:
        COVERAGE_DIRECTORY.mkdir(parents=True, exist_ok=True)
        coverage_file = COVERAGE_DIRECTORY / (
            f"{simulator.name}_{case_name}_seed{seed}_{initialization_mode}.dat"
        )
        command.extend(("--coverage", "--coverage-file", str(coverage_file)))
    if trace and simulator.supports_trace:
        TRACE_DIRECTORY.mkdir(parents=True, exist_ok=True)
        trace_file = TRACE_DIRECTORY / (
            f"{simulator.name}_{case_name}_seed{seed}_{initialization_mode}.fst"
        )
        command.extend(("--trace", str(trace_file)))

    result = subprocess.run(
        command,
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    log_file.write_text(result.stdout, encoding="utf-8")
    sys.stdout.write(result.stdout)
    if result.returncode != 0:
        raise RuntimeError(
            f"{simulator.name} failed for seed {seed} initialization "
            f"{initialization_mode}; see {log_file.relative_to(ROOT)}"
        )


def run_case(
    case_name: str,
    seed: int,
    initialization_modes: list[str],
    coverage: bool = False,
    trace: bool = False,
) -> None:
    for simulator in simulators():
        modes = initialization_modes if simulator.supports_initialization_modes else [
            initialization_modes[0]
        ]
        for mode in modes:
            run_simulator(simulator, case_name, seed, mode, coverage, trace)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run deterministic Verilator suites")
    parser.add_argument("suite", choices=("smoke", "regress", "coverage"))
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--seeds", default="1 7 19 41")
    parser.add_argument("--init-mode", default="zero")
    parser.add_argument("--init-modes", default="zero ones random")
    parser.add_argument("--trace", action="store_true")
    args = parser.parse_args()

    try:
        if args.suite == "smoke":
            run_case(
                "smoke",
                args.seed,
                parse_initialization_modes(args.init_mode),
                trace=args.trace,
            )
        else:
            if args.suite == "coverage":
                if COVERAGE_DATABASE.exists():
                    COVERAGE_DATABASE.unlink()
                if COVERAGE_DIRECTORY.exists():
                    for coverage_file in COVERAGE_DIRECTORY.glob("*.dat"):
                        coverage_file.unlink()
            initialization_modes = parse_initialization_modes(args.init_modes)
            for seed in parse_seeds(args.seeds):
                run_case(
                    "regress",
                    seed,
                    initialization_modes,
                    coverage=args.suite == "coverage",
                    trace=args.trace,
                )
            if args.suite == "coverage":
                coverage_files = tuple(COVERAGE_DIRECTORY.glob("*.dat"))
                if not coverage_files:
                    raise RuntimeError(
                        "coverage databases were not produced; build instrumented simulators"
                    )
                empty_files = tuple(path for path in coverage_files if path.stat().st_size == 0)
                if empty_files:
                    relative_path = empty_files[0].relative_to(ROOT)
                    raise RuntimeError(f"empty coverage database: {relative_path}")
    except (RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"Verilator {args.suite}: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
