class axil_agent_config extends uvm_object;
  virtual axil_if vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  `uvm_object_utils_begin(axil_agent_config)
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "axil_agent_config");
    super.new(name);
  endfunction
endclass
