class soc_base_vseq extends uvm_sequence;
  typedef logic [ELEMENT_WIDTH-1:0] element_t;

  localparam int unsigned ELEMENT_BYTES = ELEMENT_WIDTH / BITS_PER_BYTE;
  localparam int unsigned MAXIMUM_STATUS_POLLS = 10000;
  localparam addr_t TEST_DRAM_BASE = DRAM_BASE_ADDR + 32'h0001_0000;
  localparam addr_t TEST_SPM_SOURCE0 = SPM_BASE_ADDR;
  localparam addr_t TEST_SPM_SOURCE1 = SPM_BASE_ADDR + 32'h0000_1000;
  localparam addr_t TEST_SPM_DESTINATION = SPM_BASE_ADDR + 32'h0000_2000;

  `uvm_object_utils(soc_base_vseq)
  `uvm_declare_p_sequencer(soc_virtual_sequencer)

  function new(string name = "soc_base_vseq");
    super.new(name);
  endfunction

  task configure_soc();
    data_t interrupt_mask = '0;
    interrupt_mask[IRQ_DMA_DONE_BIT] = 1'b1;
    interrupt_mask[IRQ_CMD_DONE_BIT] = 1'b1;
    interrupt_mask[IRQ_ACCEL_DONE_BIT] = 1'b1;
    interrupt_mask[IRQ_ERROR_BIT] = 1'b1;
    interrupt_mask[IRQ_TIMER_BIT] = 1'b1;
    write_register(reg_pkg::REG_CTRL, register_mask(reg_pkg::CTRL_ENABLE_BIT));
    write_register(reg_pkg::REG_IRQ_ENABLE, interrupt_mask);
  endtask

  task write_register(logic [AXIL_ADDR_WIDTH-1:0] address, data_t value, strb_t strobe = '1,
                      bit expect_error = 1'b0);
    axil_access_sequence sequence_h = axil_access_sequence::type_id::create("write_sequence");
    sequence_h.direction = axil_item::AXIL_WRITE;
    sequence_h.address = address;
    sequence_h.write_data = value;
    sequence_h.write_strobe = strobe;
    sequence_h.start(p_sequencer.axil_sequencer_h);
    if (!expect_error && sequence_h.response != AXIL_RESP_OKAY) begin
      `uvm_fatal(get_type_name(), $sformatf("MMIO write failed at 0x%03x", address))
    end
    if (expect_error && sequence_h.response != AXIL_RESP_SLVERR) begin
      `uvm_error(get_type_name(), $sformatf("MMIO write did not fail at 0x%03x", address))
    end
  endtask

  task read_register(logic [AXIL_ADDR_WIDTH-1:0] address, output data_t value,
                     bit expect_error = 1'b0);
    axil_access_sequence sequence_h = axil_access_sequence::type_id::create("read_sequence");
    sequence_h.direction = axil_item::AXIL_READ;
    sequence_h.address   = address;
    sequence_h.start(p_sequencer.axil_sequencer_h);
    value = sequence_h.read_data;
    if (!expect_error && sequence_h.response != AXIL_RESP_OKAY) begin
      `uvm_fatal(get_type_name(), $sformatf("MMIO read failed at 0x%03x", address))
    end
    if (expect_error && sequence_h.response != AXIL_RESP_SLVERR) begin
      `uvm_error(get_type_name(), $sformatf("MMIO read did not fail at 0x%03x", address))
    end
  endtask

  task wait_for_status(logic [AXIL_ADDR_WIDTH-1:0] address, data_t mask, data_t expected,
                       output data_t final_value);
    for (int unsigned poll = 0; poll < MAXIMUM_STATUS_POLLS; poll++) begin
      read_register(address, final_value);
      if ((final_value & mask) == expected) begin
        return;
      end
    end
    `uvm_fatal(get_type_name(), $sformatf("Status poll timed out at 0x%03x", address))
  endtask

  task run_dma(addr_t source, addr_t destination, int unsigned length_bytes);
    data_t status;
    data_t done_mask = register_mask(
        reg_pkg::DMA_STATUS_DONE_BIT
    ) | register_mask(
        reg_pkg::DMA_STATUS_ERROR_BIT
    );

    write_register(reg_pkg::REG_DMA_STATUS, done_mask);
    write_register(reg_pkg::REG_DMA_SRC_ADDR, source);
    write_register(reg_pkg::REG_DMA_DST_ADDR, destination);
    write_register(reg_pkg::REG_DMA_LEN_BYTES, length_bytes);
    p_sequencer.scoreboard_h.expect_irq_assertion();
    write_register(reg_pkg::REG_DMA_CTRL, register_mask(reg_pkg::DMA_CTRL_START_BIT
                   ) | register_mask(reg_pkg::DMA_CTRL_IRQ_ENABLE_BIT));
    wait_for_status(reg_pkg::REG_DMA_STATUS, done_mask, register_mask(reg_pkg::DMA_STATUS_DONE_BIT),
                    status);
    if (status[reg_pkg::DMA_STATUS_ERROR_BIT]) begin
      `uvm_fatal(get_type_name(), "DMA operation completed with an error")
    end
    write_register(reg_pkg::REG_IRQ_STATUS, register_mask(IRQ_DMA_DONE_BIT));
  endtask

  task submit_command(command_desc_t command);
    soc_command_program_sequence sequence_h = soc_command_program_sequence::type_id::create(
        "command_sequence"
    );
    sequence_h.command = command;
    sequence_h.start(p_sequencer.axil_sequencer_h);
  endtask

  task wait_for_command();
    data_t status;
    data_t completion_mask = register_mask(
        reg_pkg::CMD_STATUS_DONE_BIT
    ) | register_mask(
        reg_pkg::CMD_STATUS_ERROR_BIT
    );

    wait_for_status(reg_pkg::REG_CMD_STATUS, completion_mask, register_mask(
                    reg_pkg::CMD_STATUS_DONE_BIT), status);
    if (status[reg_pkg::CMD_STATUS_ERROR_BIT]) begin
      `uvm_fatal(get_type_name(), "Accelerator command completed with an error")
    end
    write_register(reg_pkg::REG_IRQ_STATUS, register_mask(IRQ_CMD_DONE_BIT) | register_mask(
                   IRQ_ACCEL_DONE_BIT));
    write_register(reg_pkg::REG_CMD_STATUS, completion_mask);
  endtask

  task run_accelerator(command_desc_t command, addr_t dram_source0, addr_t dram_source1,
                       addr_t dram_destination, int unsigned source0_bytes,
                       int unsigned source1_bytes, int unsigned output_bytes);
    run_dma(dram_source0, command.src0_addr, source0_bytes);
    if (source1_bytes != 0) begin
      run_dma(dram_source1, command.src1_addr, source1_bytes);
    end
    p_sequencer.scoreboard_h.expect_irq_assertion();
    submit_command(command);
    wait_for_command();
    run_dma(command.dst_addr, dram_destination, output_bytes);
  endtask

  function data_t register_mask(int unsigned index);
    data_t value = '0;
    value[index] = 1'b1;
    return value;
  endfunction

  function int unsigned element_storage_bytes(int unsigned element_count);
    int unsigned byte_count = element_count * ELEMENT_BYTES;
    return ((byte_count + DATA_BYTES - 1) / DATA_BYTES) * DATA_BYTES;
  endfunction

  function void elements_to_bytes(input element_t elements[], output byte unsigned values[]);
    values = new[elements.size() * ELEMENT_BYTES];
    foreach (elements[index]) begin
      for (int unsigned byte_index = 0; byte_index < ELEMENT_BYTES; byte_index++) begin
        values[index*ELEMENT_BYTES+byte_index] =
            elements[index][byte_index*BITS_PER_BYTE+:BITS_PER_BYTE];
      end
    end
  endfunction

  function void load_elements(addr_t address, input element_t elements[]);
    byte unsigned values[];
    elements_to_bytes(elements, values);
    p_sequencer.memory_model.write_bytes(address, values);
  endfunction

  function void expect_elements(addr_t address, input element_t elements[]);
    byte unsigned values[];
    elements_to_bytes(elements, values);
    p_sequencer.scoreboard_h.expect_bytes(address, values);
  endfunction
endclass
