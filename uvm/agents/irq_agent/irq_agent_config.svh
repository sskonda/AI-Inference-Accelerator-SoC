class irq_agent_config extends uvm_object;
  virtual soc_irq_if vif;

  `uvm_object_utils(irq_agent_config)

  function new(string name = "irq_agent_config");
    super.new(name);
  endfunction
endclass
