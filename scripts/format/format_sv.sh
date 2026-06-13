#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../lib/common.sh"

root="$(repo_root)"
cd "${root}"

require_command verible-verilog-format \
  "install Verible and place verible-verilog-format on PATH"

mode="format"
if [[ "${1:-}" == "--check" ]]; then
  mode="check"
elif [[ $# -ne 0 ]]; then
  printf 'usage: %s [--check]\n' "$0" >&2
  exit 2
fi

mapfile -d '' sources < <(
  find rtl sim uvm -type f \( -name '*.sv' -o -name '*.svh' \) -print0 2>/dev/null | sort -z
)

if [[ ${#sources[@]} -eq 0 ]]; then
  printf 'Verible format: no SystemVerilog sources found\n'
  exit 0
fi

if [[ "${mode}" == "format" ]]; then
  verible-verilog-format --flagfile=.verible-format --inplace "${sources[@]}"
  printf 'Verible format: formatted %d files\n' "${#sources[@]}"
  exit 0
fi

status=0
temporary="$(mktemp)"
trap 'rm -f "${temporary}"' EXIT

for source_file in "${sources[@]}"; do
  verible-verilog-format --flagfile=.verible-format "${source_file}" >"${temporary}"
  if ! cmp -s "${source_file}" "${temporary}"; then
    printf 'format mismatch: %s\n' "${source_file}" >&2
    status=1
  fi
done

if [[ ${status} -ne 0 ]]; then
  printf 'error: run make fmt and review the changes\n' >&2
  exit "${status}"
fi

printf 'Verible format check: PASS (%d files)\n' "${#sources[@]}"
