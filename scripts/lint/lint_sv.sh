#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../lib/common.sh"

root="$(repo_root)"
cd "${root}"

require_command verible-verilog-syntax \
  "install Verible and place verible-verilog-syntax on PATH"
require_command verible-verilog-lint \
  "install Verible and place verible-verilog-lint on PATH"

mapfile -d '' sources < <(
  find rtl sim uvm -type f \( -name '*.sv' -o -name '*.svh' \) -print0 2>/dev/null | sort -z
)

if [[ ${#sources[@]} -eq 0 ]]; then
  printf 'Verible lint: no SystemVerilog sources found\n'
  exit 0
fi

verible-verilog-syntax "${sources[@]}"
verible-verilog-lint --rules_config_search "${sources[@]}"
printf 'Verible syntax and lint: PASS (%d files)\n' "${#sources[@]}"
