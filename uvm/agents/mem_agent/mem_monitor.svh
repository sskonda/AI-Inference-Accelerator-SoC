class mem_monitor extends uvm_monitor;
  `uvm_component_utils(mem_monitor)

  virtual mem_if vif;
  uvm_analysis_port #(mem_item) analysis_port;
  mem_item pending_item;
  longint unsigned cycle_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysis_port = new("analysis_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mem_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal(get_type_name(), "Memory virtual interface is not configured")
    end
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(vif.monitor_cb);
      cycle_count++;
      if (!vif.rst_n) begin
        pending_item = null;
        cycle_count  = 0;
        continue;
      end

      if (vif.monitor_cb.req_valid && vif.monitor_cb.req_ready) begin
        if (pending_item != null) begin
          `uvm_error(get_type_name(), "Multiple outstanding memory requests observed")
        end
        pending_item = mem_item::type_id::create("pending_item");
        pending_item.address = vif.monitor_cb.req_addr;
        pending_item.direction = vif.monitor_cb.req_write ? MEM_WRITE : MEM_READ;
        pending_item.write_data = vif.monitor_cb.req_wdata;
        pending_item.write_strobe = vif.monitor_cb.req_wstrb;
        pending_item.last = vif.monitor_cb.req_last;
        pending_item.request_cycle = cycle_count;
      end

      if (vif.monitor_cb.rsp_valid && vif.monitor_cb.rsp_ready) begin
        if (pending_item == null) begin
          `uvm_error(get_type_name(), "Memory response observed without a request")
        end else begin
          pending_item.read_data = vif.monitor_cb.rsp_rdata;
          pending_item.error = vif.monitor_cb.rsp_error;
          pending_item.response_cycle = cycle_count;
          analysis_port.write(pending_item);
          pending_item = null;
        end
      end
    end
  endtask
endclass
