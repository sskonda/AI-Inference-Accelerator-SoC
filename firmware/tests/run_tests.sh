#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "${script_dir}/../.." && pwd)"
build_dir="${root}/build/firmware"
compiler="${CXX:-g++}"

if ! command -v "${compiler}" >/dev/null 2>&1; then
  printf 'error: required C++ compiler not found: %s\n' "${compiler}" >&2
  exit 2
fi

mkdir -p "${build_dir}"
"${compiler}" -std=c++17 -Wall -Wextra -Werror \
  -I"${root}/firmware/include" \
  "${root}/firmware/drivers/hardware_drivers.cpp" \
  "${root}/firmware/rtos/cooperative_scheduler.cpp" \
  "${root}/firmware/workloads/workload_api.cpp" \
  "${root}/firmware/tests/firmware_tests.cpp" \
  -o "${build_dir}/firmware_tests"

"${build_dir}/firmware_tests"
