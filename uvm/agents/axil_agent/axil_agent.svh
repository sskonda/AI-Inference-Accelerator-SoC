class axil_agent extends uvm_agent;
  `uvm_component_utils(axil_agent)

  axil_agent_config config_h;
  axil_sequencer    sequencer_h;
  axil_driver       driver_h;
  axil_monitor      monitor_h;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axil_agent_config)::get(this, "", "config", config_h)) begin
      `uvm_fatal(get_type_name(), "AXI-Lite agent configuration is not set")
    end

    uvm_config_db#(virtual axil_if)::set(this, "monitor_h", "vif", config_h.vif);
    monitor_h = axil_monitor::type_id::create("monitor_h", this);

    if (config_h.is_active == UVM_ACTIVE) begin
      uvm_config_db#(virtual axil_if)::set(this, "driver_h", "vif", config_h.vif);
      sequencer_h = axil_sequencer::type_id::create("sequencer_h", this);
      driver_h    = axil_driver::type_id::create("driver_h", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (config_h.is_active == UVM_ACTIVE) begin
      driver_h.seq_item_port.connect(sequencer_h.seq_item_export);
    end
  endfunction
endclass
