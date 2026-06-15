#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REQUIRED_FILES = (
    ROOT / "README.md",
    ROOT / "LICENSE",
    ROOT / "docs" / "project_plan.md",
    ROOT / "docs" / "architecture.md",
    ROOT / "docs" / "firmware.md",
    ROOT / "docs" / "verification_plan.md",
    ROOT / "docs" / "register_map.md",
    ROOT / "docs" / "memory_map.md",
    ROOT / "docs" / "known_limitations.md",
)
LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
SKIPPED_PREFIXES = ("http://", "https://", "mailto:", "#")


def local_link_target(document: Path, raw_target: str) -> Path | None:
    target = raw_target.strip().split(maxsplit=1)[0].strip("<>")
    target = target.split("#", maxsplit=1)[0]
    if not target or target.startswith(SKIPPED_PREFIXES):
        return None
    return (document.parent / target).resolve()


def main() -> int:
    failures: list[str] = []

    for required_file in REQUIRED_FILES:
        if not required_file.is_file():
            failures.append(f"missing required document: {required_file.relative_to(ROOT)}")

    for document in sorted(ROOT.rglob("*.md")):
        if ".git" in document.parts or "build" in document.parts:
            continue
        text = document.read_text(encoding="utf-8")
        if not text.endswith("\n"):
            failures.append(f"missing final newline: {document.relative_to(ROOT)}")
        for match in LINK_PATTERN.finditer(text):
            target = local_link_target(document, match.group(1))
            if target is not None and not target.exists():
                failures.append(
                    f"broken local link in {document.relative_to(ROOT)}: {match.group(1)}"
                )

    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1

    print(f"Documentation check: PASS ({len(tuple(ROOT.rglob('*.md')))} Markdown files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
