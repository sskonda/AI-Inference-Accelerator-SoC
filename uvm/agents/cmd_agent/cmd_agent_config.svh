class cmd_agent_config extends uvm_object;
  virtual soc_command_monitor_if vif;

  `uvm_object_utils(cmd_agent_config)

  function new(string name = "cmd_agent_config");
    super.new(name);
  endfunction
endclass
