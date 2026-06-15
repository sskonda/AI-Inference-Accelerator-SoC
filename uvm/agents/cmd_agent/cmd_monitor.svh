class cmd_monitor extends uvm_monitor;
  `uvm_component_utils(cmd_monitor)

  virtual soc_command_monitor_if vif;
  uvm_analysis_port #(cmd_item) analysis_port;
  longint unsigned cycle_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysis_port = new("analysis_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual soc_command_monitor_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal(get_type_name(), "Command monitor interface is not configured")
    end
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(vif.monitor_cb);
      cycle_count++;
      if (!vif.rst_n) begin
        cycle_count = 0;
      end else if (vif.monitor_cb.command_completed) begin
        cmd_item item = cmd_item::type_id::create("item");
        item.command_id = vif.monitor_cb.command_id;
        item.opcode = vif.monitor_cb.opcode;
        item.error = vif.monitor_cb.error;
        item.queue_occupancy = vif.monitor_cb.queue_occupancy;
        item.cycle = cycle_count;
        analysis_port.write(item);
      end
    end
  endtask
endclass
