class mem_agent_config extends uvm_object;
  virtual mem_if vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  int unsigned ready_percent = 80;
  int unsigned maximum_response_latency = 3;
  int unsigned error_percent = 0;
  soc_memory_model memory;

  `uvm_object_utils_begin(mem_agent_config)
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_DEFAULT)
    `uvm_field_int(ready_percent, UVM_DEC)
    `uvm_field_int(maximum_response_latency, UVM_DEC)
    `uvm_field_int(error_percent, UVM_DEC)
    `uvm_field_object(memory, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "mem_agent_config");
    super.new(name);
    memory = soc_memory_model::type_id::create("memory");
  endfunction
endclass
