class soc_base_test extends uvm_test;
  `uvm_component_utils(soc_base_test)

  soc_env_config config_h;
  soc_env env_h;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    config_h = soc_env_config::type_id::create("config_h");
    if (!uvm_config_db#(virtual axil_if)::get(this, "", "axil_vif", config_h.axil_vif)) begin
      `uvm_fatal(get_type_name(), "AXI-Lite interface is not configured")
    end
    if (!uvm_config_db#(virtual mem_if)::get(this, "", "memory_vif", config_h.memory_vif)) begin
      `uvm_fatal(get_type_name(), "Memory interface is not configured")
    end
    if (!uvm_config_db#(virtual soc_irq_if)::get(this, "", "irq_vif", config_h.irq_vif)) begin
      `uvm_fatal(get_type_name(), "IRQ interface is not configured")
    end
    if (!uvm_config_db#(virtual soc_command_monitor_if)::get(
            this, "", "command_vif", config_h.command_vif
        )) begin
      `uvm_fatal(get_type_name(), "Command monitor interface is not configured")
    end
    if (!uvm_config_db#(virtual soc_reset_if)::get(this, "", "reset_vif", config_h.reset_vif)) begin
      `uvm_fatal(get_type_name(), "Reset interface is not configured")
    end
    uvm_config_db#(soc_env_config)::set(this, "env_h", "config", config_h);
    env_h = soc_env::type_id::create("env_h", this);
  endfunction

  virtual function soc_base_vseq create_sequence();
    return null;
  endfunction

  task run_phase(uvm_phase phase);
    soc_base_vseq sequence_h = create_sequence();
    if (sequence_h == null) begin
      `uvm_fatal(get_type_name(), "Test did not provide a virtual sequence")
    end
    phase.raise_objection(this);
    sequence_h.start(env_h.virtual_sequencer_h);
    phase.drop_objection(this);
  endtask
endclass

class smoke_test extends soc_base_test;
  `uvm_component_utils(smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    return soc_smoke_vseq::type_id::create("sequence_h");
  endfunction
endclass

class register_test extends soc_base_test;
  `uvm_component_utils(register_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    return soc_register_vseq::type_id::create("sequence_h");
  endfunction
endclass

class dma_directed_test extends soc_base_test;
  `uvm_component_utils(dma_directed_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    return soc_dma_directed_vseq::type_id::create("sequence_h");
  endfunction
endclass

class dma_random_test extends soc_base_test;
  `uvm_component_utils(dma_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    return soc_dma_random_vseq::type_id::create("sequence_h");
  endfunction
endclass

class vector_directed_test extends soc_base_test;
  `uvm_component_utils(vector_directed_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    soc_vector_vseq sequence_h = soc_vector_vseq::type_id::create("sequence_h");
    sequence_h.random_mode = 1'b0;
    return sequence_h;
  endfunction
endclass

class vector_random_test extends soc_base_test;
  `uvm_component_utils(vector_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    soc_vector_vseq sequence_h = soc_vector_vseq::type_id::create("sequence_h");
    sequence_h.random_mode = 1'b1;
    return sequence_h;
  endfunction
endclass

class reduction_directed_test extends soc_base_test;
  `uvm_component_utils(reduction_directed_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    soc_reduction_vseq sequence_h = soc_reduction_vseq::type_id::create("sequence_h");
    sequence_h.random_mode = 1'b0;
    return sequence_h;
  endfunction
endclass

class reduction_random_test extends soc_base_test;
  `uvm_component_utils(reduction_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    soc_reduction_vseq sequence_h = soc_reduction_vseq::type_id::create("sequence_h");
    sequence_h.random_mode = 1'b1;
    return sequence_h;
  endfunction
endclass

class gemm_directed_test extends soc_base_test;
  `uvm_component_utils(gemm_directed_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    soc_gemm_vseq sequence_h = soc_gemm_vseq::type_id::create("sequence_h");
    sequence_h.random_mode = 1'b0;
    return sequence_h;
  endfunction
endclass

class gemm_random_test extends soc_base_test;
  `uvm_component_utils(gemm_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    soc_gemm_vseq sequence_h = soc_gemm_vseq::type_id::create("sequence_h");
    sequence_h.random_mode = 1'b1;
    return sequence_h;
  endfunction
endclass

class command_queue_random_test extends soc_base_test;
  `uvm_component_utils(command_queue_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    return soc_command_queue_vseq::type_id::create("sequence_h");
  endfunction
endclass

class irq_test extends soc_base_test;
  `uvm_component_utils(irq_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    return soc_irq_vseq::type_id::create("sequence_h");
  endfunction
endclass

class reset_test extends soc_base_test;
  `uvm_component_utils(reset_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    return soc_reset_vseq::type_id::create("sequence_h");
  endfunction
endclass

class backpressure_test extends soc_base_test;
  `uvm_component_utils(backpressure_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    config_h.memory_config.ready_percent = 25;
    config_h.memory_config.maximum_response_latency = 8;
  endfunction

  function soc_base_vseq create_sequence();
    return soc_dma_random_vseq::type_id::create("sequence_h");
  endfunction
endclass

class mixed_workload_test extends soc_base_test;
  `uvm_component_utils(mixed_workload_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    return soc_mixed_workload_vseq::type_id::create("sequence_h");
  endfunction
endclass

class error_injection_test extends soc_base_test;
  `uvm_component_utils(error_injection_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    return soc_error_injection_vseq::type_id::create("sequence_h");
  endfunction
endclass

class performance_counter_test extends soc_base_test;
  `uvm_component_utils(performance_counter_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function soc_base_vseq create_sequence();
    return soc_performance_vseq::type_id::create("sequence_h");
  endfunction
endclass
