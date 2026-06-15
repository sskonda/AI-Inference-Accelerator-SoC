#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../lib/common.sh"

root="$(repo_root)"
cd "${root}"

require_command verilator "install Verilator and place verilator on PATH"
require_file "sim/scripts/run_verilator.py" \
  "complete the Verilator harness milestone before requesting coverage"
require_file "scripts/coverage/summarize_verilator_coverage.py" \
  "restore the Verilator coverage summary script"

rm -rf coverage
mkdir -p coverage

export VERILATOR_BUILD_DIR="${VERILATOR_BUILD_DIR:-build/verilator_coverage}"
export VERILATOR_COVERAGE=1

bash sim/scripts/verilator_flow.sh build
python3 sim/scripts/run_verilator.py coverage --seeds "${SEEDS:-1 7 19 41}" \
  --init-modes "${INIT_MODES:-zero ones random}"

coverage_inputs=(coverage/verilator/*.dat)
reporter_status="verilator_coverage not found"
if command -v verilator_coverage >/dev/null 2>&1; then
  if verilator_coverage --annotate coverage/annotated "${coverage_inputs[@]}" \
    > coverage/verilator_coverage.log 2>&1; then
    reporter_status="verilator_coverage annotate passed"
  else
    reporter_status="verilator_coverage annotate unavailable; see coverage/verilator_coverage.log"
    printf 'warning: %s\n' "${reporter_status}" >&2
  fi
else
  printf 'warning: %s\n' "${reporter_status}" >&2
fi

python3 scripts/coverage/summarize_verilator_coverage.py \
  --reporter-status "${reporter_status}" \
  "${coverage_inputs[@]}" > coverage/summary.txt

{
  printf 'Verilator coverage databases: %s\n' "${#coverage_inputs[@]}"
  printf 'Coverage data: coverage/verilator/*.dat\n'
} >> coverage/summary.txt

printf 'Coverage report written to coverage/summary.txt\n'
