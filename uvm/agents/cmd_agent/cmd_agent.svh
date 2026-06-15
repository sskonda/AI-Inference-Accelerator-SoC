class cmd_agent extends uvm_agent;
  `uvm_component_utils(cmd_agent)

  cmd_agent_config config_h;
  cmd_monitor monitor_h;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(cmd_agent_config)::get(this, "", "config", config_h)) begin
      `uvm_fatal(get_type_name(), "Command agent configuration is not set")
    end
    uvm_config_db#(virtual soc_command_monitor_if)::set(this, "monitor_h", "vif", config_h.vif);
    monitor_h = cmd_monitor::type_id::create("monitor_h", this);
  endfunction
endclass
