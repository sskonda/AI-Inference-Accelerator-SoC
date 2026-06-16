#!/usr/bin/env bash

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "${root}"

rm -rf build coverage logs work reports/synth
rm -f transcript modelsim.ini vsim.wlf
find . -type d -name __pycache__ -prune -exec rm -rf {} +
find . -type f \( -name '*.pyc' -o -name '*.vcd' -o -name '*.fst' \) -delete

printf 'Clean: removed simulation and report outputs\n'
