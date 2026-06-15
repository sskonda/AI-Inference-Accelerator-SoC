class mem_agent extends uvm_agent;
  `uvm_component_utils(mem_agent)

  mem_agent_config config_h;
  mem_responder responder_h;
  mem_monitor monitor_h;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(mem_agent_config)::get(this, "", "config", config_h)) begin
      `uvm_fatal(get_type_name(), "Memory agent configuration is not set")
    end
    uvm_config_db#(virtual mem_if)::set(this, "monitor_h", "vif", config_h.vif);
    monitor_h = mem_monitor::type_id::create("monitor_h", this);
    if (config_h.is_active == UVM_ACTIVE) begin
      uvm_config_db#(mem_agent_config)::set(this, "responder_h", "config", config_h);
      responder_h = mem_responder::type_id::create("responder_h", this);
    end
  endfunction
endclass
