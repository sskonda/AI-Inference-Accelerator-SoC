#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../lib/common.sh"

root="$(repo_root)"
cd "${root}"

require_command yosys "install OSS CAD Suite or another Yosys build with the slang frontend"
require_file "rtl/files.f" "restore the ordered RTL source list"
require_file "scripts/synth/summarize_yosys_stat.py" "restore the Yosys stat parser"

top="${SYNTH_TOP:-soc_top}"
if [[ ! "${top}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  printf 'error: invalid synthesis top name: %s\n' "${top}" >&2
  exit 2
fi

if ! yosys -m slang -p 'help read_slang' >/dev/null 2>&1; then
  printf 'error: Yosys slang frontend is unavailable\n' >&2
  printf 'hint: install OSS CAD Suite or a Yosys build containing yosys-slang-plugin\n' >&2
  exit 2
fi

report_dir="reports/synth"
mkdir -p "${report_dir}"

log_path="${report_dir}/${top}_yosys_stat.log"
json_path="${report_dir}/${top}_yosys_summary.json"
markdown_path="${report_dir}/${top}_yosys_summary.md"

yosys -m slang -p "\
read_slang --top ${top} --ignore-assertions --ignore-initial -f rtl/files.f; \
hierarchy -top ${top}; \
proc; \
opt; \
stat" > "${log_path}"

python3 scripts/synth/summarize_yosys_stat.py \
  --top "${top}" \
  --log "${log_path}" \
  --json "${json_path}" \
  --markdown "${markdown_path}"

printf 'Yosys estimate written to %s and %s\n' "${json_path}" "${markdown_path}"
