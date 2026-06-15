package soc_uvm_pkg;
  import uvm_pkg::*;
  import soc_pkg::*;
  import reg_pkg::*;
  import accel_pkg::*;
  import axil_agent_pkg::*;
  import mem_agent_pkg::*;
  import irq_agent_pkg::*;
  import cmd_agent_pkg::*;

  `include "uvm_macros.svh"

`uvm_analysis_imp_decl(_axil_sb)
  `uvm_analysis_imp_decl(_mem_sb)
  `uvm_analysis_imp_decl(_irq_sb)
  `uvm_analysis_imp_decl(_cmd_sb)
  `uvm_analysis_imp_decl(_mem_cov)
  `uvm_analysis_imp_decl(_irq_cov)
  `uvm_analysis_imp_decl(_cmd_cov)

  `include "soc_env_config.svh"
  `include "soc_reference_model.svh"
  `include "soc_scoreboard.svh"
  `include "soc_coverage.svh"
  `include "soc_virtual_sequencer.svh"
  `include "soc_env.svh"
  `include "axil_access_sequence.svh"
  `include "command_sequence_library.svh"
  `include "soc_base_vseq.svh"
  `include "soc_virtual_sequences.svh"
  `include "soc_tests.svh"
endpackage
