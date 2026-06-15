class soc_env_config extends uvm_object;
  virtual axil_if axil_vif;
  virtual mem_if memory_vif;
  virtual soc_irq_if irq_vif;
  virtual soc_command_monitor_if command_vif;
  virtual soc_reset_if reset_vif;
  axil_agent_config axil_config;
  mem_agent_config memory_config;
  irq_agent_config irq_config;
  cmd_agent_config command_config;

  `uvm_object_utils_begin(soc_env_config)
    `uvm_field_object(axil_config, UVM_DEFAULT)
    `uvm_field_object(memory_config, UVM_DEFAULT)
    `uvm_field_object(irq_config, UVM_DEFAULT)
    `uvm_field_object(command_config, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "soc_env_config");
    super.new(name);
    axil_config = axil_agent_config::type_id::create("axil_config");
    memory_config = mem_agent_config::type_id::create("memory_config");
    irq_config = irq_agent_config::type_id::create("irq_config");
    command_config = cmd_agent_config::type_id::create("command_config");
  endfunction

  function void bind_interfaces();
    axil_config.vif = axil_vif;
    memory_config.vif = memory_vif;
    irq_config.vif = irq_vif;
    command_config.vif = command_vif;
  endfunction
endclass
