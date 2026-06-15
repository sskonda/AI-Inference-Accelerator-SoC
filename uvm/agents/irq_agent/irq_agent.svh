class irq_agent extends uvm_agent;
  `uvm_component_utils(irq_agent)

  irq_agent_config config_h;
  irq_monitor monitor_h;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(irq_agent_config)::get(this, "", "config", config_h)) begin
      `uvm_fatal(get_type_name(), "IRQ agent configuration is not set")
    end
    uvm_config_db#(virtual soc_irq_if)::set(this, "monitor_h", "vif", config_h.vif);
    monitor_h = irq_monitor::type_id::create("monitor_h", this);
  endfunction
endclass
