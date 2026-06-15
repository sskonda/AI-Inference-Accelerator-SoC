class axil_driver extends uvm_driver #(axil_item);
  `uvm_component_utils(axil_driver)

  virtual axil_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal(get_type_name(), "AXI-Lite virtual interface is not configured")
    end
  endfunction

  task run_phase(uvm_phase phase);
    axil_item item;

    drive_idle();
    forever begin
      wait_for_reset_release();
      seq_item_port.get_next_item(item);
      if (item.direction == axil_item::AXIL_WRITE) begin
        drive_write(item);
      end else begin
        drive_read(item);
      end
      seq_item_port.item_done();
    end
  endtask

  task drive_idle();
    vif.manager_cb.awvalid <= 1'b0;
    vif.manager_cb.awaddr  <= '0;
    vif.manager_cb.wvalid  <= 1'b0;
    vif.manager_cb.wdata   <= '0;
    vif.manager_cb.wstrb   <= '0;
    vif.manager_cb.bready  <= 1'b0;
    vif.manager_cb.arvalid <= 1'b0;
    vif.manager_cb.araddr  <= '0;
    vif.manager_cb.rready  <= 1'b0;
  endtask

  task wait_for_reset_release();
    while (!vif.rst_n) begin
      @(vif.manager_cb);
      drive_idle();
    end
  endtask

  task drive_write(axil_item item);
    bit address_pending = 1'b1;
    bit data_pending = 1'b1;

    vif.manager_cb.awvalid <= 1'b1;
    vif.manager_cb.awaddr  <= item.address;
    vif.manager_cb.wvalid  <= 1'b1;
    vif.manager_cb.wdata   <= item.write_data;
    vif.manager_cb.wstrb   <= item.write_strobe;
    vif.manager_cb.bready  <= 1'b1;

    forever begin
      @(vif.manager_cb);
      if (!vif.rst_n) begin
        drive_idle();
        wait_for_reset_release();
        item.response = AXIL_RESP_SLVERR;
        return;
      end
      if (address_pending && vif.manager_cb.awready) begin
        address_pending = 1'b0;
        vif.manager_cb.awvalid <= 1'b0;
      end
      if (data_pending && vif.manager_cb.wready) begin
        data_pending = 1'b0;
        vif.manager_cb.wvalid <= 1'b0;
      end
      if (!address_pending && !data_pending && vif.manager_cb.bvalid) begin
        item.response = axil_resp_e'(vif.manager_cb.bresp);
        vif.manager_cb.bready <= 1'b0;
        return;
      end
    end
  endtask

  task drive_read(axil_item item);
    bit address_pending = 1'b1;

    vif.manager_cb.arvalid <= 1'b1;
    vif.manager_cb.araddr  <= item.address;
    vif.manager_cb.rready  <= 1'b1;

    forever begin
      @(vif.manager_cb);
      if (!vif.rst_n) begin
        drive_idle();
        wait_for_reset_release();
        item.response = AXIL_RESP_SLVERR;
        return;
      end
      if (address_pending && vif.manager_cb.arready) begin
        address_pending = 1'b0;
        vif.manager_cb.arvalid <= 1'b0;
      end
      if (!address_pending && vif.manager_cb.rvalid) begin
        item.read_data = vif.manager_cb.rdata;
        item.response  = axil_resp_e'(vif.manager_cb.rresp);
        vif.manager_cb.rready <= 1'b0;
        return;
      end
    end
  endtask
endclass
