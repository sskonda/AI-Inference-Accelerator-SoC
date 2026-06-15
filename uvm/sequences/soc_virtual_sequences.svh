class soc_smoke_vseq extends soc_base_vseq;
  `uvm_object_utils(soc_smoke_vseq)

  function new(string name = "soc_smoke_vseq");
    super.new(name);
  endfunction

  task body();
    byte unsigned source                                               [];
    addr_t        source_address = TEST_DRAM_BASE;
    addr_t        destination_address = TEST_DRAM_BASE + 32'h0000_1000;

    source = new[19];
    foreach (source[index]) begin
      source[index] = byte'((index * 17) + 3);
    end
    configure_soc();
    p_sequencer.memory_model.write_bytes(source_address, source);
    p_sequencer.scoreboard_h.expect_bytes(destination_address, source);
    run_dma(source_address, destination_address, source.size());
  endtask
endclass

class soc_register_vseq extends soc_base_vseq;
  `uvm_object_utils(soc_register_vseq)

  function new(string name = "soc_register_vseq");
    super.new(name);
  endfunction

  task body();
    data_t value;
    read_register(reg_pkg::REG_SOC_ID, value);
    if (value != reg_pkg::SOC_ID_VALUE) begin
      `uvm_error(get_type_name(), "SOC_ID mismatch")
    end
    read_register(reg_pkg::REG_VERSION, value);
    if (value != reg_pkg::VERSION_VALUE) begin
      `uvm_error(get_type_name(), "VERSION mismatch")
    end
    write_register(reg_pkg::REG_IRQ_ENABLE, '1);
    read_register(reg_pkg::REG_IRQ_ENABLE, value);
    write_register(reg_pkg::REG_SOC_ID, '1, '1, 1'b1);
    read_register(12'h0fc, value, 1'b1);
    write_register(reg_pkg::REG_ERROR_STATUS, '1);
  endtask
endclass

class soc_dma_directed_vseq extends soc_base_vseq;
  `uvm_object_utils(soc_dma_directed_vseq)

  function new(string name = "soc_dma_directed_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned lengths[] = '{1, DATA_BYTES, 19, 32};
    configure_soc();
    foreach (lengths[test_index]) begin
      byte unsigned source[] = new[lengths[test_index]];
      addr_t source_address = TEST_DRAM_BASE + addr_t'(test_index * 32'h0000_1000);
      addr_t destination_address = TEST_DRAM_BASE + 32'h0000_8000 +
          addr_t'(test_index * 32'h0000_1000);
      foreach (source[index]) begin
        source[index] = byte'((test_index * 31) + index);
      end
      p_sequencer.memory_model.write_bytes(source_address, source);
      p_sequencer.scoreboard_h.expect_bytes(destination_address, source);
      run_dma(source_address, destination_address, source.size());
    end
  endtask
endclass

class soc_dma_random_vseq extends soc_base_vseq;
  `uvm_object_utils(soc_dma_random_vseq)

  function new(string name = "soc_dma_random_vseq");
    super.new(name);
  endfunction

  task body();
    configure_soc();
    repeat (12) begin
      int unsigned length = $urandom_range(96, 1);
      int unsigned slot = $urandom_range(31, 0);
      byte unsigned source[] = new[length];
      addr_t source_address = TEST_DRAM_BASE + addr_t'(slot * 32'h0000_1000);
      addr_t destination_address = TEST_DRAM_BASE + 32'h0004_0000 + addr_t'(slot * 32'h0000_1000);
      foreach (source[index]) begin
        source[index] = byte'($urandom());
      end
      p_sequencer.memory_model.write_bytes(source_address, source);
      p_sequencer.scoreboard_h.expect_bytes(destination_address, source);
      run_dma(source_address, destination_address, source.size());
    end
  endtask
endclass

class soc_vector_vseq extends soc_base_vseq;
  rand command_opcode_e selected_opcode;
  rand int unsigned selected_length;
  bit random_mode;

  constraint opcode_c {
    selected_opcode inside {CMD_OP_VECTOR_ADD, CMD_OP_VECTOR_MULTIPLY, CMD_OP_VECTOR_SCALE,
                            CMD_OP_VECTOR_RELU, CMD_OP_VECTOR_CLAMP};
  }
  constraint length_c {selected_length inside {[1 : 32]};}

  `uvm_object_utils_begin(soc_vector_vseq)
    `uvm_field_enum(command_opcode_e, selected_opcode, UVM_DEFAULT)
    `uvm_field_int(selected_length, UVM_DEC)
    `uvm_field_int(random_mode, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "soc_vector_vseq");
    super.new(name);
  endfunction

  task body();
    command_opcode_e operations[];
    configure_soc();
    if (random_mode) begin
      operations = new[12];
      foreach (operations[index]) begin
        if (!randomize()) begin
          `uvm_fatal(get_type_name(), "Vector sequence randomization failed")
        end
        operations[index] = selected_opcode;
        run_operation(operations[index], selected_length, index);
      end
    end else begin
      operations = '{
          CMD_OP_VECTOR_ADD,
          CMD_OP_VECTOR_MULTIPLY,
          CMD_OP_VECTOR_SCALE,
          CMD_OP_VECTOR_RELU,
          CMD_OP_VECTOR_CLAMP
      };
      foreach (operations[index]) begin
        run_operation(operations[index], 7, index);
      end
    end
  endtask

  task run_operation(command_opcode_e opcode, int unsigned length, int unsigned slot);
    element_t source0[] = new[length];
    element_t source1[];
    element_t expected[];
    command_desc_t command = '0;
    addr_t dram_source0 = TEST_DRAM_BASE + addr_t'(slot * 32'h0000_2000);
    addr_t dram_source1 = dram_source0 + 32'h0000_0800;
    addr_t dram_destination = TEST_DRAM_BASE + 32'h0005_0000 + addr_t'(slot * 32'h0000_1000);
    int unsigned source1_count = opcode == CMD_OP_VECTOR_RELU ?
        0 : (opcode == CMD_OP_VECTOR_SCALE ? 1 : length);

    source1 = new[source1_count];
    foreach (source0[index]) begin
      source0[index] = element_t'($urandom());
    end
    foreach (source1[index]) begin
      source1[index] = element_t'($urandom());
    end
    load_elements(dram_source0, source0);
    if (source1_count != 0) begin
      load_elements(dram_source1, source1);
    end
    soc_reference_model::vector_operation(opcode, source0, source1, 1'b1, 1'b1, expected);
    expect_elements(dram_destination, expected);

    command.opcode = opcode;
    command.src0_addr = TEST_SPM_SOURCE0;
    command.src1_addr = TEST_SPM_SOURCE1;
    command.dst_addr = TEST_SPM_DESTINATION;
    command.length = LENGTH_WIDTH'(length);
    command.flags[FLAG_SIGNED_BIT] = 1'b1;
    command.flags[FLAG_SATURATE_BIT] = 1'b1;
    command.flags[FLAG_IRQ_ON_DONE_BIT] = 1'b1;
    command.priority_level = PRIORITY_WIDTH'($urandom_range(7, 0));
    command.command_id = COMMAND_ID_WIDTH'(16'h200 + slot);

    run_accelerator(command, dram_source0, dram_source1, dram_destination, element_storage_bytes(
                    length), source1_count == 0 ? 0 : element_storage_bytes(source1_count),
                    length * ELEMENT_BYTES);
  endtask
endclass

class soc_reduction_vseq extends soc_base_vseq;
  bit random_mode;

  `uvm_object_utils_begin(soc_reduction_vseq)
    `uvm_field_int(random_mode, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "soc_reduction_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned lengths[];
    configure_soc();
    if (random_mode) begin
      lengths = new[12];
      foreach (lengths[index]) begin
        lengths[index] = $urandom_range(64, 1);
      end
    end else begin
      lengths = '{1, 5, 8, 31};
    end
    foreach (lengths[index]) begin
      run_operation(index[0] ? CMD_OP_REDUCE_MAX : CMD_OP_REDUCE_SUM, lengths[index], index);
    end
  endtask

  task run_operation(command_opcode_e opcode, int unsigned length, int unsigned slot);
    element_t source[] = new[length];
    element_t expected[] = new[1];
    command_desc_t command = '0;
    addr_t dram_source = TEST_DRAM_BASE + addr_t'(slot * 32'h0000_1000);
    addr_t dram_destination = TEST_DRAM_BASE + 32'h0006_0000 + addr_t'(slot * 32'h0000_0100);

    foreach (source[index]) begin
      source[index] = element_t'($urandom());
    end
    load_elements(dram_source, source);
    expected[0] = soc_reference_model::reduction_operation(opcode, source, 1'b1, 1'b1);
    expect_elements(dram_destination, expected);

    command.opcode = opcode;
    command.src0_addr = TEST_SPM_SOURCE0;
    command.dst_addr = TEST_SPM_DESTINATION;
    command.length = LENGTH_WIDTH'(length);
    command.flags[FLAG_SIGNED_BIT] = 1'b1;
    command.flags[FLAG_SATURATE_BIT] = 1'b1;
    command.flags[FLAG_IRQ_ON_DONE_BIT] = 1'b1;
    command.command_id = COMMAND_ID_WIDTH'(16'h300 + slot);
    run_accelerator(command, dram_source, '0, dram_destination, element_storage_bytes(length), 0,
                    ELEMENT_BYTES);
  endtask
endclass

class soc_gemm_vseq extends soc_base_vseq;
  bit random_mode;

  `uvm_object_utils_begin(soc_gemm_vseq)
    `uvm_field_int(random_mode, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "soc_gemm_vseq");
    super.new(name);
  endfunction

  task body();
    configure_soc();
    if (random_mode) begin
      repeat (10) begin
        run_matrix($urandom_range(4, 1), $urandom_range(4, 1), $urandom_range(4, 1), $urandom_range(
                   15, 0));
      end
    end else begin
      run_matrix(1, 1, 1, 0);
      run_matrix(3, 3, 3, 1);
      run_matrix(2, 4, 3, 2);
      run_matrix(4, 2, 1, 3);
    end
  endtask

  task run_matrix(int unsigned rows, int unsigned columns, int unsigned inner, int unsigned slot);
    element_t matrix_a[] = new[rows * inner];
    element_t matrix_b[] = new[inner * columns];
    element_t expected[];
    command_desc_t command = '0;
    addr_t dram_source0 = TEST_DRAM_BASE + addr_t'(slot * 32'h0000_2000);
    addr_t dram_source1 = dram_source0 + 32'h0000_0800;
    addr_t dram_destination = TEST_DRAM_BASE + 32'h0007_0000 + addr_t'(slot * 32'h0000_0400);

    foreach (matrix_a[index]) begin
      matrix_a[index] = element_t'($urandom_range(15, 0));
    end
    foreach (matrix_b[index]) begin
      matrix_b[index] = element_t'($urandom_range(15, 0));
    end
    load_elements(dram_source0, matrix_a);
    load_elements(dram_source1, matrix_b);
    soc_reference_model::gemm_operation(matrix_a, matrix_b, rows, columns, inner, 1'b0, 1'b0,
                                        expected);
    expect_elements(dram_destination, expected);

    command.opcode = CMD_OP_GEMM;
    command.src0_addr = TEST_SPM_SOURCE0;
    command.src1_addr = TEST_SPM_SOURCE1;
    command.dst_addr = TEST_SPM_DESTINATION;
    command.m = DIMENSION_WIDTH'(rows);
    command.n = DIMENSION_WIDTH'(columns);
    command.k = DIMENSION_WIDTH'(inner);
    command.flags[FLAG_IRQ_ON_DONE_BIT] = 1'b1;
    command.command_id = COMMAND_ID_WIDTH'(16'h400 + slot);
    run_accelerator(command, dram_source0, dram_source1, dram_destination, element_storage_bytes(
                    rows * inner), element_storage_bytes(inner * columns),
                    rows * columns * ELEMENT_BYTES);
  endtask
endclass

class soc_command_queue_vseq extends soc_base_vseq;
  `uvm_object_utils(soc_command_queue_vseq)

  function new(string name = "soc_command_queue_vseq");
    super.new(name);
  endfunction

  task body();
    data_t queue_status;
    configure_soc();
    write_register(reg_pkg::REG_CTRL, '0);
    write_register(reg_pkg::REG_SCHED_CTRL, register_mask(reg_pkg::SCHED_POLICY_BIT
                   ) | data_t'(DEFAULT_STARVATION_THRESHOLD << reg_pkg::SCHED_STARVATION_LSB));
    repeat (DEFAULT_COMMAND_QUEUE_DEPTH) begin
      command_desc_t command = '0;
      int unsigned   index = accepted_index++;
      command.opcode = CMD_OP_DMA_COPY;
      command.src0_addr = TEST_DRAM_BASE + addr_t'(index * DATA_BYTES);
      command.dst_addr = TEST_SPM_SOURCE0 + addr_t'(index * DATA_BYTES);
      command.length = DATA_BYTES;
      command.priority_level = PRIORITY_WIDTH'(index);
      command.command_id = COMMAND_ID_WIDTH'(16'h500 + index);
      submit_command(command);
    end
    read_register(reg_pkg::REG_QUEUE_STATUS, queue_status);
    if (!queue_status[reg_pkg::QUEUE_FULL_BIT]) begin
      `uvm_error(get_type_name(), "Command queue did not report full")
    end
    submit_full_queue_command();
    p_sequencer.scoreboard_h.expect_irq_assertion();
    write_register(reg_pkg::REG_CTRL, register_mask(reg_pkg::CTRL_ENABLE_BIT));
    for (int unsigned cycle = 0; cycle < MAXIMUM_STATUS_POLLS; cycle++) begin
      if (p_sequencer.scoreboard_h.accepted_command_ids.size() == 0) begin
        write_register(reg_pkg::REG_IRQ_STATUS, register_mask(IRQ_CMD_DONE_BIT) | register_mask(
                       IRQ_DMA_DONE_BIT));
        write_register(reg_pkg::REG_CMD_STATUS, register_mask(reg_pkg::CMD_STATUS_DONE_BIT
                       ) | register_mask(reg_pkg::CMD_STATUS_ERROR_BIT));
        return;
      end
      @(posedge p_sequencer.reset_vif.clk);
    end
    `uvm_fatal(get_type_name(), "Queued commands did not all retire")
  endtask

  task submit_full_queue_command();
    write_register(reg_pkg::REG_CMD_OPCODE, CMD_OP_DMA_COPY);
    write_register(reg_pkg::REG_CMD_SRC0_ADDR, TEST_DRAM_BASE);
    write_register(reg_pkg::REG_CMD_SRC1_ADDR, '0);
    write_register(reg_pkg::REG_CMD_DST_ADDR, TEST_SPM_SOURCE0);
    write_register(reg_pkg::REG_CMD_LEN, DATA_BYTES);
    write_register(reg_pkg::REG_CMD_M, '0);
    write_register(reg_pkg::REG_CMD_N, '0);
    write_register(reg_pkg::REG_CMD_K, '0);
    write_register(reg_pkg::REG_CMD_FLAGS, '0);
    write_register(reg_pkg::REG_CMD_PRIORITY, '0);
    write_register(reg_pkg::REG_CMD_ID, 16'h5ff);
    write_register(reg_pkg::REG_CMD_SUBMIT, register_mask(reg_pkg::CMD_SUBMIT_BIT), '1, 1'b1);
    write_register(reg_pkg::REG_ERROR_STATUS, register_mask(ERR_QUEUE_FULL));
  endtask

  int unsigned accepted_index;
endclass

class soc_irq_vseq extends soc_base_vseq;
  `uvm_object_utils(soc_irq_vseq)

  function new(string name = "soc_irq_vseq");
    super.new(name);
  endfunction

  task body();
    data_t status;
    data_t timer_mask = register_mask(IRQ_TIMER_BIT);
    configure_soc();
    p_sequencer.scoreboard_h.expect_irq_assertion();
    write_register(reg_pkg::REG_TIMER_CTRL, register_mask(reg_pkg::TIMER_ENABLE_BIT
                   ) | register_mask(reg_pkg::TIMER_PERIODIC_BIT
                   ) | data_t'(8 << reg_pkg::TIMER_INTERVAL_LSB));
    wait_for_status(reg_pkg::REG_IRQ_STATUS, timer_mask, timer_mask, status);
    write_register(reg_pkg::REG_IRQ_STATUS, timer_mask);
    write_register(reg_pkg::REG_IRQ_ENABLE, '0);
    write_register(reg_pkg::REG_TIMER_CTRL, '0);
  endtask
endclass

class soc_reset_vseq extends soc_base_vseq;
  `uvm_object_utils(soc_reset_vseq)

  function new(string name = "soc_reset_vseq");
    super.new(name);
  endfunction

  task body();
    byte unsigned source [] = new[64];
    data_t        status;
    configure_soc();
    foreach (source[index]) begin
      source[index] = byte'($urandom());
    end
    p_sequencer.memory_model.write_bytes(TEST_DRAM_BASE, source);
    write_register(reg_pkg::REG_DMA_SRC_ADDR, TEST_DRAM_BASE);
    write_register(reg_pkg::REG_DMA_DST_ADDR, TEST_SPM_SOURCE0);
    write_register(reg_pkg::REG_DMA_LEN_BYTES, source.size());
    write_register(reg_pkg::REG_DMA_CTRL, register_mask(reg_pkg::DMA_CTRL_START_BIT));
    p_sequencer.reset_vif.apply_reset(3);
    read_register(reg_pkg::REG_DMA_STATUS, status);
    if (status[reg_pkg::DMA_STATUS_BUSY_BIT]) begin
      `uvm_error(get_type_name(), "DMA remained busy after reset")
    end
  endtask
endclass

class soc_mixed_workload_vseq extends soc_base_vseq;
  `uvm_object_utils(soc_mixed_workload_vseq)

  function new(string name = "soc_mixed_workload_vseq");
    super.new(name);
  endfunction

  task body();
    soc_dma_directed_vseq dma_sequence = soc_dma_directed_vseq::type_id::create("dma_sequence");
    soc_vector_vseq vector_sequence = soc_vector_vseq::type_id::create("vector_sequence");
    soc_reduction_vseq reduction_sequence = soc_reduction_vseq::type_id::create(
        "reduction_sequence"
    );
    dma_sequence.start(p_sequencer);
    vector_sequence.start(p_sequencer);
    reduction_sequence.start(p_sequencer);
  endtask
endclass

class soc_error_injection_vseq extends soc_base_vseq;
  `uvm_object_utils(soc_error_injection_vseq)

  function new(string name = "soc_error_injection_vseq");
    super.new(name);
  endfunction

  task body();
    data_t value;
    data_t error_mask = register_mask(reg_pkg::DMA_STATUS_ERROR_BIT);
    configure_soc();
    read_register(12'h0fc, value, 1'b1);
    write_register(reg_pkg::REG_DMA_SRC_ADDR, 32'h7000_0000);
    write_register(reg_pkg::REG_DMA_DST_ADDR, TEST_SPM_SOURCE0);
    write_register(reg_pkg::REG_DMA_LEN_BYTES, DATA_BYTES);
    p_sequencer.scoreboard_h.expect_irq_assertion();
    write_register(reg_pkg::REG_DMA_CTRL, register_mask(reg_pkg::DMA_CTRL_START_BIT));
    wait_for_status(reg_pkg::REG_DMA_STATUS, error_mask, error_mask, value);
    write_register(reg_pkg::REG_DMA_STATUS, error_mask);
    write_register(reg_pkg::REG_ERROR_STATUS, '1);
    write_register(reg_pkg::REG_IRQ_STATUS, register_mask(IRQ_ERROR_BIT));
  endtask
endclass

class soc_performance_vseq extends soc_base_vseq;
  `uvm_object_utils(soc_performance_vseq)

  function new(string name = "soc_performance_vseq");
    super.new(name);
  endfunction

  task body();
    soc_smoke_vseq smoke_sequence = soc_smoke_vseq::type_id::create("smoke_sequence");
    data_t         low_value;
    data_t         high_value;
    smoke_sequence.start(p_sequencer);
    write_register(reg_pkg::REG_PERF_SELECT, PERF_TOTAL_CYCLES);
    read_register(reg_pkg::REG_PERF_VALUE, low_value);
    read_register(reg_pkg::REG_PERF_VALUE_HI, high_value);
    if ({high_value, low_value} == '0) begin
      `uvm_error(get_type_name(), "Total-cycle performance counter remained zero")
    end
  endtask
endclass
