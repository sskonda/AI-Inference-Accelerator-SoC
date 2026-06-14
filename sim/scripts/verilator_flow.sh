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
    if [[ -f "rtl/soc/soc_top.sv" ]]; then
      verilator --lint-only --timing --assert -Wall --top-module soc_top -f rtl/files.f
    elif [[ -f "sim/verilator/primitive_test_top.sv" ]]; then
      verilator --lint-only --timing --assert -Wall \
        --top-module primitive_test_top \
        -f rtl/files.f \
        sim/common/protocol_compile_top.sv \
        sim/verilator/primitive_test_top.sv
    else
      require_file "sim/common/protocol_compile_top.sv" \
        "complete the protocol compile top used before SoC integration"
      verilator --lint-only --timing --assert -Wall \
        --top-module protocol_compile_top \
        -f rtl/files.f \
        sim/common/protocol_compile_top.sv
    fi
    ;;
  build)
    mkdir -p build/verilator
    if [[ -f "rtl/soc/soc_top.sv" ]]; then
      require_file "sim/verilator/sim_main.cpp" \
        "complete the SoC Verilator harness before building"
      verilator --cc --exe --build --timing --assert --trace-fst -Wall \
        --top-module soc_top \
        -Mdir build/verilator \
        -f rtl/files.f \
        "${root}/sim/verilator/sim_main.cpp"
    else
      require_file "sim/verilator/primitive_test_top.sv" \
        "complete the primitive simulation top before building"
      require_file "sim/verilator/primitive_main.cpp" \
        "complete the primitive C++ test program before building"
      verilator --cc --exe --build --timing --assert --trace-fst -Wall \
        --top-module primitive_test_top \
        -Mdir build/verilator \
        -CFLAGS "-std=c++17" \
        -f rtl/files.f \
        sim/common/protocol_compile_top.sv \
        sim/verilator/primitive_test_top.sv \
        "${root}/sim/verilator/primitive_main.cpp"
    fi
    ;;
  *)
    printf 'usage: %s {lint|build}\n' "$0" >&2
    exit 2
    ;;
esac
