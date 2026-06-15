#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../../scripts/lib/common.sh"

root="$(repo_root)"
cd "${root}"

require_command vlog \
  "install a Questa-compatible simulator with UVM support and place vlog on PATH"
require_command vsim \
  "install a Questa-compatible simulator with UVM support and place vsim on PATH"
require_command vlib \
  "install a Questa-compatible simulator with UVM support and place vlib on PATH"
require_file "uvm/files.f" "complete the UVM environment milestone"
require_file "rtl/files.f" "complete the synthesizable RTL source list"

action="${1:-}"
mkdir -p build/uvm logs

find_uvm_source() {
  local candidate
  for candidate in \
    "${UVM_HOME:-}" \
    "${QUESTA_HOME:-}/verilog_src/uvm-1.2/src" \
    "${MTI_HOME:-}/verilog_src/uvm-1.2/src"; do
    if [[ -n "${candidate}" && -f "${candidate}/uvm_pkg.sv" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  printf 'error: UVM source directory was not found\n' >&2
  printf 'hint: set UVM_HOME to the directory containing uvm_pkg.sv and uvm_macros.svh\n' >&2
  return 2
}

compile_uvm() {
  local uvm_source
  uvm_source="$(find_uvm_source)"
  rm -rf build/uvm/work
  vlib build/uvm/work
  vlog -work build/uvm/work -sv -mfcu \
    "+incdir+${uvm_source}" \
    "${uvm_source}/uvm_pkg.sv" \
    -f rtl/files.f \
    -f uvm/files.f
}

run_uvm_test() {
  local test_name="$1"
  local seed="$2"
  local log_file="$3"
  local simulator_status

  set +e
  vsim -c -lib build/uvm/work tb_top \
    "+UVM_TESTNAME=${test_name}" "-sv_seed" "${seed}" \
    -do "run -all; quit -f" | tee "${log_file}"
  simulator_status="${PIPESTATUS[0]}"
  set -e

  if [[ "${simulator_status}" -ne 0 ]]; then
    printf 'error: UVM simulator failed for %s seed %s\n' "${test_name}" "${seed}" >&2
    return "${simulator_status}"
  fi
  if ! grep -Eq 'UVM_ERROR[[:space:]]*:[[:space:]]*0' "${log_file}" ||
    ! grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*0' "${log_file}"; then
    printf 'error: UVM report summary is not clean for %s seed %s\n' \
      "${test_name}" "${seed}" >&2
    return 1
  fi
}

case "${action}" in
  compile)
    compile_uvm
    ;;
  smoke)
    test_name="${2:-smoke_test}"
    seed="${3:-1}"
    compile_uvm
    run_uvm_test "${test_name}" "${seed}" "logs/uvm_${test_name}_${seed}.log"
    ;;
  regress)
    seeds="${2:-1 7 19 41}"
    require_file "tests/regressions/uvm_tests.txt" \
      "complete the UVM regression manifest"
    compile_uvm
    while IFS= read -r test_name; do
      [[ -z "${test_name}" || "${test_name}" == \#* ]] && continue
      for seed in ${seeds}; do
        log_file="logs/uvm_${test_name}_${seed}.log"
        run_uvm_test "${test_name}" "${seed}" "${log_file}"
      done
    done <tests/regressions/uvm_tests.txt
    ;;
  *)
    printf 'usage: %s {compile|smoke|regress}\n' "$0" >&2
    exit 2
    ;;
esac
