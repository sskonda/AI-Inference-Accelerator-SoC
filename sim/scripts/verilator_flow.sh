#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../../scripts/lib/common.sh"

root="$(repo_root)"
cd "${root}"

require_command verilator "install Verilator and place verilator on PATH"
require_file "rtl/files.f" "complete the RTL source-list milestone"

lint_top() {
  local top="$1"
  shift
  verilator --lint-only --timing --assert -Wall \
    --top-module "${top}" \
    -f rtl/files.f \
    "$@"
}

build_top() {
  local top="$1"
  local main_source="$2"
  local compiler_flags="$3"
  shift 3

  require_file "${main_source}" "complete the ${top} C++ test program before building"
  verilator --cc --exe --build --timing --assert --trace-fst -Wall \
    --top-module "${top}" \
    -Mdir build/verilator \
    -CFLAGS "${compiler_flags}" \
    -f rtl/files.f \
    "$@" \
    "${root}/${main_source}"
}

action="${1:-}"
case "${action}" in
  lint)
    if [[ -f "rtl/soc/soc_top.sv" ]]; then
      lint_top soc_top
    fi

    lint_top primitive_test_top \
      sim/common/protocol_compile_top.sv \
      sim/verilator/primitive_test_top.sv

    if [[ -f "sim/verilator/register_test_top.sv" ]]; then
      lint_top register_test_top \
        sim/common/protocol_compile_top.sv \
        sim/verilator/register_test_top.sv
    fi
    if [[ -f "sim/verilator/dma_test_top.sv" ]]; then
      lint_top dma_test_top \
        -GDATA_WIDTH=64 \
        -GMAX_BURST_BEATS=3 \
        sim/common/protocol_compile_top.sv \
        sim/verilator/dma_test_top.sv
    fi
    if [[ -f "sim/verilator/services_test_top.sv" ]]; then
      lint_top services_test_top \
        -GTIMER_WIDTH=24 \
        -GTEST_COUNTER_WIDTH=64 \
        -GIRQ_LATENCY_WIDTH=32 \
        sim/common/protocol_compile_top.sv \
        sim/verilator/services_test_top.sv
    fi
    if [[ -f "sim/verilator/command_test_top.sv" ]]; then
      lint_top command_test_top \
        -GQUEUE_DEPTH=5 \
        -GAGE_WIDTH=6 \
        sim/common/protocol_compile_top.sv \
        sim/verilator/command_test_top.sv
    fi
    if [[ -f "sim/verilator/vector_test_top.sv" ]]; then
      lint_top vector_test_top \
        sim/common/protocol_compile_top.sv \
        sim/verilator/vector_test_top.sv
    fi
    if [[ -f "sim/verilator/reduction_test_top.sv" ]]; then
      lint_top reduction_test_top \
        sim/common/protocol_compile_top.sv \
        sim/verilator/reduction_test_top.sv
    fi
    if [[ -f "sim/verilator/gemm_test_top.sv" ]]; then
      lint_top gemm_test_top \
        sim/common/protocol_compile_top.sv \
        sim/verilator/gemm_test_top.sv
    fi
    ;;

  build)
    mkdir -p build/verilator

    if [[ -f "rtl/soc/soc_top.sv" ]]; then
      build_top soc_top sim/verilator/sim_main.cpp \
        "-std=c++17 -I${root}/firmware/include -I${root}/models/cpp" \
        "${root}/firmware/drivers/hardware_drivers.cpp" \
        "${root}/firmware/rtos/cooperative_scheduler.cpp" \
        "${root}/firmware/workloads/workload_api.cpp"
    fi

    build_top primitive_test_top sim/verilator/primitive_main.cpp \
      "-std=c++17" \
      sim/common/protocol_compile_top.sv \
      sim/verilator/primitive_test_top.sv

    if [[ -f "sim/verilator/register_test_top.sv" ]]; then
      build_top register_test_top sim/verilator/register_main.cpp \
        "-std=c++17 -I${root}/firmware/include" \
        sim/common/protocol_compile_top.sv \
        sim/verilator/register_test_top.sv
    fi
    if [[ -f "sim/verilator/dma_test_top.sv" ]]; then
      build_top dma_test_top sim/verilator/dma_main.cpp \
        "-std=c++17 -I${root}/firmware/include" \
        sim/common/protocol_compile_top.sv \
        sim/verilator/dma_test_top.sv
    fi
    if [[ -f "sim/verilator/services_test_top.sv" ]]; then
      build_top services_test_top sim/verilator/services_main.cpp \
        "-std=c++17 -I${root}/firmware/include" \
        sim/common/protocol_compile_top.sv \
        sim/verilator/services_test_top.sv
    fi
    if [[ -f "sim/verilator/command_test_top.sv" ]]; then
      build_top command_test_top sim/verilator/command_main.cpp \
        "-std=c++17 -I${root}/firmware/include" \
        sim/common/protocol_compile_top.sv \
        sim/verilator/command_test_top.sv
    fi
    if [[ -f "sim/verilator/vector_test_top.sv" ]]; then
      build_top vector_test_top sim/verilator/vector_main.cpp \
        "-std=c++17 -I${root}/firmware/include -I${root}/models/cpp" \
        sim/common/protocol_compile_top.sv \
        sim/verilator/vector_test_top.sv
    fi
    if [[ -f "sim/verilator/reduction_test_top.sv" ]]; then
      build_top reduction_test_top sim/verilator/reduction_main.cpp \
        "-std=c++17 -I${root}/firmware/include -I${root}/models/cpp" \
        sim/common/protocol_compile_top.sv \
        sim/verilator/reduction_test_top.sv
    fi
    if [[ -f "sim/verilator/gemm_test_top.sv" ]]; then
      build_top gemm_test_top sim/verilator/gemm_main.cpp \
        "-std=c++17 -I${root}/firmware/include -I${root}/models/cpp" \
        sim/common/protocol_compile_top.sv \
        sim/verilator/gemm_test_top.sv
    fi
    ;;

  *)
    printf 'usage: %s {lint|build}\n' "$0" >&2
    exit 2
    ;;
esac
