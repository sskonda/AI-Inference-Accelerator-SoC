#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FILELIST = ROOT / "uvm" / "files.f"
MANIFEST = ROOT / "tests" / "regressions" / "uvm_tests.txt"
PACKAGE = ROOT / "uvm" / "packages" / "soc_uvm_pkg.sv"

REQUIRED_TESTS = (
    "smoke_test",
    "register_test",
    "dma_directed_test",
    "dma_random_test",
    "vector_directed_test",
    "vector_random_test",
    "reduction_directed_test",
    "reduction_random_test",
    "gemm_directed_test",
    "gemm_random_test",
    "command_queue_random_test",
    "irq_test",
    "reset_test",
    "backpressure_test",
    "mixed_workload_test",
    "error_injection_test",
    "performance_counter_test",
)

REQUIRED_CLASSES = (
    "soc_base_test",
    "soc_env",
    "soc_env_config",
    "soc_virtual_sequencer",
    "soc_scoreboard",
    "soc_reference_model",
    "soc_coverage",
    "axil_agent",
    "mem_agent",
    "mem_responder",
    "irq_agent",
    "cmd_agent",
    *REQUIRED_TESTS,
)


def source_text() -> str:
    parts: list[str] = []
    for path in sorted((ROOT / "uvm").rglob("*.sv*")):
        parts.append(path.read_text(encoding="utf-8"))
    return "\n".join(parts)


def filelist_paths() -> tuple[list[Path], list[Path]]:
    sources: list[Path] = []
    include_dirs: list[Path] = []
    for raw_line in FILELIST.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("+incdir+"):
            include_dirs.append(ROOT / line.removeprefix("+incdir+"))
        elif line.startswith(("+", "-")):
            continue
        else:
            sources.append(ROOT / line)
    return sources, include_dirs


def main() -> int:
    failures: list[str] = []

    for required in (FILELIST, MANIFEST, PACKAGE, ROOT / "sim" / "uvm" / "tb_top.sv"):
        if not required.is_file():
            failures.append(f"missing UVM artifact: {required.relative_to(ROOT)}")

    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1

    sources, include_dirs = filelist_paths()
    for path in (*sources, *include_dirs):
        if not path.exists():
            failures.append(f"missing file-list path: {path.relative_to(ROOT)}")

    text = source_text()
    for class_name in REQUIRED_CLASSES:
        if re.search(rf"\bclass\s+{re.escape(class_name)}\b", text) is None:
            failures.append(f"missing UVM class: {class_name}")

    for test_name in REQUIRED_TESTS:
        registration = rf"`uvm_component_utils\s*\(\s*{re.escape(test_name)}\s*\)"
        if re.search(registration, text) is None:
            failures.append(f"test is not factory registered: {test_name}")

    manifest_tests = tuple(
        line.strip()
        for line in MANIFEST.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )
    if manifest_tests != REQUIRED_TESTS:
        failures.append("UVM regression manifest does not match the required ordered test list")
    if len(set(manifest_tests)) != len(manifest_tests):
        failures.append("UVM regression manifest contains duplicate tests")

    package_text = PACKAGE.read_text(encoding="utf-8")
    included_headers = set(re.findall(r'`include\s+"([^"]+\.svh)"', package_text))
    for package_path in (
        ROOT / "uvm" / "packages" / "axil_agent_pkg.sv",
        ROOT / "uvm" / "packages" / "mem_agent_pkg.sv",
        ROOT / "uvm" / "packages" / "irq_agent_pkg.sv",
        ROOT / "uvm" / "packages" / "cmd_agent_pkg.sv",
    ):
        included_headers.update(
            re.findall(r'`include\s+"([^"]+\.svh)"', package_path.read_text(encoding="utf-8"))
        )

    for header in sorted((ROOT / "uvm").rglob("*.svh")):
        if header.name not in included_headers:
            failures.append(f"UVM header is not included by a package: {header.relative_to(ROOT)}")

    expected_source_order = (
        "uvm/packages/axil_agent_pkg.sv",
        "uvm/packages/mem_agent_pkg.sv",
        "uvm/packages/irq_agent_pkg.sv",
        "uvm/packages/cmd_agent_pkg.sv",
        "uvm/packages/soc_uvm_pkg.sv",
        "uvm/assertions/soc_top_assertions.sv",
        "sim/uvm/tb_top.sv",
    )
    listed = [str(path.relative_to(ROOT)) for path in sources]
    positions = [listed.index(name) if name in listed else -1 for name in expected_source_order]
    if any(position < 0 for position in positions) or positions != sorted(positions):
        failures.append("UVM package, bind, and top-level source order is invalid")

    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1

    print(
        "UVM structure check: PASS "
        f"({len(sources)} compilation units, {len(REQUIRED_TESTS)} tests)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
