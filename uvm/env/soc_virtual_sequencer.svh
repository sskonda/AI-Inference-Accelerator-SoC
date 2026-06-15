class soc_virtual_sequencer extends uvm_sequencer;
  `uvm_component_utils(soc_virtual_sequencer)

  axil_sequencer axil_sequencer_h;
  soc_memory_model memory_model;
  soc_scoreboard scoreboard_h;
  virtual soc_reset_if reset_vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
