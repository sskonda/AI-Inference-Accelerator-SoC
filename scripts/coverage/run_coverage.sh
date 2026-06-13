#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../lib/common.sh"

root="$(repo_root)"
cd "${root}"

require_command verilator "install Verilator and place verilator on PATH"
require_file "sim/scripts/run_verilator.py" \
  "complete the Verilator harness milestone before requesting coverage"

python3 sim/scripts/run_verilator.py coverage --seeds "1 7 19 41"
