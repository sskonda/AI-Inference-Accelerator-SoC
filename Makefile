SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

SEED ?= 1
SEEDS ?= 1 7 19 41
UVM_TEST ?= smoke_test
UVM_SEED ?= 1
UVM_SEEDS ?= 1 7 19 41

.PHONY: help fmt fmt-check lint verilator-lint verilator-build verilator-smoke
.PHONY: verilator-regress uvm-compile uvm-smoke uvm-regress coverage docs clean ci

help:
	@printf '%s\n' \
	  'Inference Accelerator SoC simulation targets' \
	  '' \
	  '  make help                Show this target list' \
	  '  make fmt                 Format SystemVerilog sources with Verible' \
	  '  make lint                Run Verible syntax and lint checks' \
	  '  make verilator-lint      Lint synthesizable RTL with Verilator' \
	  '  make verilator-build     Build the cycle-accurate C++ simulator' \
	  '  make verilator-smoke     Run the deterministic smoke suite' \
	  '  make verilator-regress   Run the non-UVM regression' \
	  '  make uvm-compile         Compile the class-based testbench' \
	  '  make uvm-smoke           Run one UVM smoke test' \
	  '  make uvm-regress         Run the UVM regression list' \
	  '  make coverage            Produce available coverage reports' \
	  '  make docs                Validate documentation structure and links' \
	  '  make clean               Remove simulation and report outputs' \
	  '  make ci                  Run the open-source closure suite' \
	  '' \
	  'Variables:' \
	  '  SEED=<n>                 Smoke-test seed (default: 1)' \
	  '  SEEDS="<n> ..."          Regression seeds (default: 1 7 19 41)' \
	  '  UVM_TEST=<name>          UVM smoke test (default: smoke_test)' \
	  '  UVM_SEED=<n>             UVM smoke seed (default: 1)' \
	  '  UVM_SEEDS="<n> ..."      UVM regression seeds'

fmt:
	@bash scripts/format/format_sv.sh

fmt-check:
	@bash scripts/format/format_sv.sh --check

lint:
	@bash scripts/lint/lint_sv.sh

verilator-lint:
	@bash sim/scripts/verilator_flow.sh lint

verilator-build:
	@bash sim/scripts/verilator_flow.sh build

verilator-smoke:
	@python3 sim/scripts/run_verilator.py smoke --seed "$(SEED)"

verilator-regress:
	@python3 sim/scripts/run_verilator.py regress --seeds "$(SEEDS)"

uvm-compile:
	@bash sim/scripts/uvm_flow.sh compile

uvm-smoke:
	@bash sim/scripts/uvm_flow.sh smoke "$(UVM_TEST)" "$(UVM_SEED)"

uvm-regress:
	@bash sim/scripts/uvm_flow.sh regress "$(UVM_SEEDS)"

coverage:
	@bash scripts/coverage/run_coverage.sh

docs:
	@python3 scripts/docs/check_docs.py
	@python3 scripts/docs/check_register_map.py
	@python3 scripts/docs/check_memory_map.py

clean:
	@bash scripts/clean.sh

ci: fmt-check lint verilator-lint verilator-build verilator-regress docs
