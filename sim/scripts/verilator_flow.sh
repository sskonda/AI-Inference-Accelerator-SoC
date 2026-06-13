#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../../scripts/lib/common.sh"

root="$(repo_root)"
cd "${root}"

require_command verilator "install Verilator and place verilator on PATH"
require_file "rtl/files.f" "complete the RTL source-list milestone"

action="${1:-}"
case "${action}" in
  lint)
    verilator --lint-only --timing -Wall -f rtl/files.f
    ;;
  build)
    require_file "sim/verilator/sim_main.cpp" \
      "complete the Verilator harness milestone before building"
    verilator --cc --exe --build --timing --trace-fst -Wall \
      --top-module soc_top \
      -Mdir build/verilator \
      -f rtl/files.f \
      sim/verilator/sim_main.cpp
    ;;
  *)
    printf 'usage: %s {lint|build}\n' "$0" >&2
    exit 2
    ;;
esac
