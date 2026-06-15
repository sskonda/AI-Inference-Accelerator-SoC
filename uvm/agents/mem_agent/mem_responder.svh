class mem_responder extends uvm_component;
  `uvm_component_utils(mem_responder)

  virtual mem_if vif;
  mem_agent_config config_h;

  bit response_pending;
  bit response_valid_driven;
  bit request_ready_driven;
  data_t response_data;
  bit response_error;
  int unsigned response_delay;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(mem_agent_config)::get(this, "", "config", config_h)) begin
      `uvm_fatal(get_type_name(), "Memory agent configuration is not set")
    end
    vif = config_h.vif;
    if (config_h.ready_percent > 100 || config_h.error_percent > 100) begin
      `uvm_fatal(get_type_name(), "Memory response percentages must be at most 100")
    end
  endfunction

  task run_phase(uvm_phase phase);
    drive_idle();
    forever begin
      @(vif.target_cb);
      if (!vif.rst_n) begin
        drive_idle();
        continue;
      end

      if (response_valid_driven && vif.target_cb.rsp_ready) begin
        response_valid_driven = 1'b0;
        response_pending = 1'b0;
        vif.target_cb.rsp_valid <= 1'b0;
      end

      if (response_pending && !response_valid_driven) begin
        if (response_delay == 0) begin
          response_valid_driven = 1'b1;
          vif.target_cb.rsp_valid <= 1'b1;
          vif.target_cb.rsp_rdata <= response_data;
          vif.target_cb.rsp_error <= response_error;
        end else begin
          response_delay--;
        end
      end

      if (!response_pending && request_ready_driven && vif.target_cb.req_valid) begin
        accept_request();
      end

      request_ready_driven = !response_pending && ($urandom_range(99, 0) < config_h.ready_percent);
      vif.target_cb.req_ready <= request_ready_driven;
    end
  endtask

  task drive_idle();
    response_pending = 1'b0;
    response_valid_driven = 1'b0;
    request_ready_driven = 1'b0;
    response_data = '0;
    response_error = 1'b0;
    response_delay = 0;
    vif.target_cb.req_ready <= 1'b0;
    vif.target_cb.rsp_valid <= 1'b0;
    vif.target_cb.rsp_rdata <= '0;
    vif.target_cb.rsp_error <= 1'b0;
  endtask

  task accept_request();
    addr_t address = vif.target_cb.req_addr;
    bit injected_error = config_h.error_percent != 0 && ($urandom_range(
        99, 0
    ) < config_h.error_percent);

    response_pending = 1'b1;
    response_delay = $urandom_range(config_h.maximum_response_latency, 0);
    response_error = !config_h.memory.address_is_legal(address) || injected_error;
    response_data = '0;
    if (!response_error) begin
      if (vif.target_cb.req_write) begin
        config_h.memory.write_word(address, vif.target_cb.req_wdata, vif.target_cb.req_wstrb);
      end else begin
        response_data = config_h.memory.read_word(address);
      end
    end
  endtask
endclass
