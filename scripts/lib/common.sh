#!/usr/bin/env bash

set -euo pipefail

repo_root() {
  git rev-parse --show-toplevel
}

require_command() {
  local command_name="$1"
  local install_hint="$2"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'error: required tool not found: %s\n' "${command_name}" >&2
    printf 'hint: %s\n' "${install_hint}" >&2
    exit 2
  fi
}

require_file() {
  local file_path="$1"
  local producing_target="$2"

  if [[ ! -f "${file_path}" ]]; then
    printf 'error: required file not found: %s\n' "${file_path}" >&2
    printf 'hint: %s\n' "${producing_target}" >&2
    exit 2
  fi
}
