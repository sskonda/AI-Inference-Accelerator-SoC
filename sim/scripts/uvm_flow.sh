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
require_file "uvm/files.f" "complete the UVM environment milestone"

action="${1:-}"
mkdir -p build/uvm logs

compile_uvm() {
  rm -rf build/uvm/work
  vlib build/uvm/work
  vlog -work build/uvm/work -sv -f uvm/files.f
}

case "${action}" in
  compile)
    compile_uvm
    ;;
  smoke)
    test_name="${2:-smoke_test}"
    seed="${3:-1}"
    compile_uvm
    vsim -c -lib build/uvm/work tb_top \
      "+UVM_TESTNAME=${test_name}" "-sv_seed" "${seed}" \
      -do "run -all; quit -f"
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
        vsim -c -lib build/uvm/work tb_top \
          "+UVM_TESTNAME=${test_name}" "-sv_seed" "${seed}" \
          -do "run -all; quit -f" | tee "${log_file}"
      done
    done <tests/regressions/uvm_tests.txt
    ;;
  *)
    printf 'usage: %s {compile|smoke|regress}\n' "$0" >&2
    exit 2
    ;;
esac
