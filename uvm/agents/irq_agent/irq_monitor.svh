class irq_monitor extends uvm_monitor;
  `uvm_component_utils(irq_monitor)

  virtual soc_irq_if vif;
  uvm_analysis_port #(irq_item) analysis_port;
  bit previous_irq;
  longint unsigned cycle_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysis_port = new("analysis_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual soc_irq_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal(get_type_name(), "IRQ virtual interface is not configured")
    end
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(vif.monitor_cb);
      cycle_count++;
      if (!vif.rst_n) begin
        previous_irq = 1'b0;
        cycle_count  = 0;
      end else if (vif.monitor_cb.irq != previous_irq) begin
        irq_item item = irq_item::type_id::create("item");
        item.asserted = vif.monitor_cb.irq;
        item.cycle = cycle_count;
        analysis_port.write(item);
        previous_irq = vif.monitor_cb.irq;
      end
    end
  endtask
endclass
