class soc_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(soc_scoreboard)

  uvm_analysis_imp_axil_sb #(axil_item, soc_scoreboard) axil_export;
  uvm_analysis_imp_mem_sb #(mem_item, soc_scoreboard) memory_export;
  uvm_analysis_imp_irq_sb #(irq_item, soc_scoreboard) irq_export;
  uvm_analysis_imp_cmd_sb #(cmd_item, soc_scoreboard) command_export;

  byte unsigned expected_bytes[addr_t];
  bit expected_observed[addr_t];
  logic [COMMAND_ID_WIDTH-1:0] staged_command_id;
  command_opcode_e staged_opcode;
  logic [COMMAND_ID_WIDTH-1:0] accepted_command_ids[$];
  command_opcode_e accepted_opcodes[$];
  int unsigned expected_irq_assertions;
  int unsigned irq_assertions;
  int unsigned irq_deassertions;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    axil_export = new("axil_export", this);
    memory_export = new("memory_export", this);
    irq_export = new("irq_export", this);
    command_export = new("command_export", this);
  endfunction

  function void expect_bytes(addr_t address, input byte unsigned values[]);
    foreach (values[index]) begin
      addr_t byte_address = address + addr_t'(index);
      expected_bytes[byte_address] = values[index];
      expected_observed[byte_address] = 1'b0;
    end
  endfunction

  function void expect_irq_assertion();
    expected_irq_assertions++;
  endfunction

  function void write_axil_sb(axil_item item);
    if (item.direction == axil_item::AXIL_WRITE && item.response == AXIL_RESP_OKAY) begin
      case (item.address)
        reg_pkg::REG_CMD_ID: staged_command_id = item.write_data[COMMAND_ID_WIDTH-1:0];
        reg_pkg::REG_CMD_OPCODE:
        staged_opcode = command_opcode_e'(item.write_data[OPCODE_WIDTH-1:0]);
        reg_pkg::REG_CMD_SUBMIT: begin
          if (item.write_data[reg_pkg::CMD_SUBMIT_BIT]) begin
            accepted_command_ids.push_back(staged_command_id);
            accepted_opcodes.push_back(staged_opcode);
          end
        end
        default: begin
        end
      endcase
    end
  endfunction

  function void write_mem_sb(mem_item item);
    if (item.direction != MEM_WRITE || item.error) begin
      return;
    end

    for (int unsigned byte_index = 0; byte_index < DATA_BYTES; byte_index++) begin
      addr_t byte_address = item.address + addr_t'(byte_index);
      if (!item.write_strobe[byte_index]) begin
        continue;
      end
      if (!expected_bytes.exists(byte_address)) begin
        `uvm_error(get_type_name(), $sformatf("Unexpected external-memory write at 0x%08x",
                                              byte_address))
        continue;
      end
      if (expected_observed[byte_address]) begin
        `uvm_error(get_type_name(), $sformatf("Duplicate external-memory write at 0x%08x",
                                              byte_address))
      end
      begin
        byte unsigned observed = item.write_data[byte_index*BITS_PER_BYTE+:BITS_PER_BYTE];
        if (observed != expected_bytes[byte_address]) begin
          `uvm_error(get_type_name(),
                     $sformatf("Memory mismatch at 0x%08x: expected 0x%02x observed 0x%02x",
                               byte_address, expected_bytes[byte_address], observed))
        end
        expected_observed[byte_address] = 1'b1;
      end
    end
  endfunction

  function void write_irq_sb(irq_item item);
    if (item.asserted) begin
      irq_assertions++;
      if (expected_irq_assertions == 0) begin
        `uvm_error(get_type_name(), "Unexpected external interrupt assertion")
      end else begin
        expected_irq_assertions--;
      end
    end else begin
      irq_deassertions++;
    end
  endfunction

  function void write_cmd_sb(cmd_item item);
    int match_index = -1;

    foreach (accepted_command_ids[index]) begin
      if (accepted_command_ids[index] == item.command_id) begin
        match_index = index;
        break;
      end
    end
    if (match_index < 0) begin
      `uvm_error(get_type_name(), $sformatf("Unexpected or duplicate command completion ID 0x%04x",
                                            item.command_id))
      return;
    end
    if (accepted_opcodes[match_index] != item.opcode) begin
      `uvm_error(get_type_name(), $sformatf("Completion opcode mismatch for command ID 0x%04x",
                                            item.command_id))
    end
    if (item.error) begin
      `uvm_error(get_type_name(), $sformatf("Command ID 0x%04x completed with an error",
                                            item.command_id))
    end
    accepted_command_ids.delete(match_index);
    accepted_opcodes.delete(match_index);
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    foreach (expected_observed[address]) begin
      if (!expected_observed[address]) begin
        `uvm_error(get_type_name(), $sformatf("Expected memory byte at 0x%08x was not observed",
                                              address))
      end
    end
    if (accepted_command_ids.size() != 0) begin
      `uvm_error(get_type_name(), $sformatf("%0d accepted commands were not retired",
                                            accepted_command_ids.size()))
    end
    if (expected_irq_assertions != 0) begin
      `uvm_error(get_type_name(), $sformatf("%0d expected interrupt assertions were not observed",
                                            expected_irq_assertions))
    end
  endfunction
endclass
