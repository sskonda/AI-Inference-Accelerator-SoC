class axil_monitor extends uvm_monitor;
  `uvm_component_utils(axil_monitor)

  virtual axil_if vif;
  uvm_analysis_port #(axil_item) analysis_port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysis_port = new("analysis_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal(get_type_name(), "AXI-Lite virtual interface is not configured")
    end
  endfunction

  task run_phase(uvm_phase phase);
    logic [AXIL_ADDR_WIDTH-1:0] write_address;
    logic [     DATA_WIDTH-1:0] write_data;
    logic [     STRB_WIDTH-1:0] write_strobe;
    logic [AXIL_ADDR_WIDTH-1:0] read_address;
    bit                         have_write_address = 1'b0;
    bit                         have_write_data = 1'b0;
    bit                         have_read_address = 1'b0;

    forever begin
      @(vif.monitor_cb);
      if (!vif.rst_n) begin
        have_write_address = 1'b0;
        have_write_data    = 1'b0;
        have_read_address  = 1'b0;
        continue;
      end

      if (vif.monitor_cb.awvalid && vif.monitor_cb.awready) begin
        write_address      = vif.monitor_cb.awaddr;
        have_write_address = 1'b1;
      end
      if (vif.monitor_cb.wvalid && vif.monitor_cb.wready) begin
        write_data      = vif.monitor_cb.wdata;
        write_strobe    = vif.monitor_cb.wstrb;
        have_write_data = 1'b1;
      end
      if (vif.monitor_cb.bvalid && vif.monitor_cb.bready) begin
        axil_item item = axil_item::type_id::create("write_item");
        if (!(have_write_address && have_write_data)) begin
          `uvm_error(get_type_name(), "Write response observed without a complete request")
        end
        item.direction    = axil_item::AXIL_WRITE;
        item.address      = write_address;
        item.write_data   = write_data;
        item.write_strobe = write_strobe;
        item.response     = axil_resp_e'(vif.monitor_cb.bresp);
        analysis_port.write(item);
        have_write_address = 1'b0;
        have_write_data    = 1'b0;
      end

      if (vif.monitor_cb.arvalid && vif.monitor_cb.arready) begin
        read_address      = vif.monitor_cb.araddr;
        have_read_address = 1'b1;
      end
      if (vif.monitor_cb.rvalid && vif.monitor_cb.rready) begin
        axil_item item = axil_item::type_id::create("read_item");
        if (!have_read_address) begin
          `uvm_error(get_type_name(), "Read response observed without a request")
        end
        item.direction = axil_item::AXIL_READ;
        item.address   = read_address;
        item.read_data = vif.monitor_cb.rdata;
        item.response  = axil_resp_e'(vif.monitor_cb.rresp);
        analysis_port.write(item);
        have_read_address = 1'b0;
      end
    end
  endtask
endclass
