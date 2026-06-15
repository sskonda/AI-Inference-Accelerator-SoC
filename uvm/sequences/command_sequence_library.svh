class soc_command_program_sequence extends uvm_sequence #(axil_item);
  `uvm_object_utils(soc_command_program_sequence)

  command_desc_t command;

  function new(string name = "soc_command_program_sequence");
    super.new(name);
  endfunction

  task body();
    write_register(reg_pkg::REG_CMD_OPCODE, command.opcode);
    write_register(reg_pkg::REG_CMD_SRC0_ADDR, command.src0_addr);
    write_register(reg_pkg::REG_CMD_SRC1_ADDR, command.src1_addr);
    write_register(reg_pkg::REG_CMD_DST_ADDR, command.dst_addr);
    write_register(reg_pkg::REG_CMD_LEN, command.length);
    write_register(reg_pkg::REG_CMD_M, command.m);
    write_register(reg_pkg::REG_CMD_N, command.n);
    write_register(reg_pkg::REG_CMD_K, command.k);
    write_register(reg_pkg::REG_CMD_FLAGS, command.flags);
    write_register(reg_pkg::REG_CMD_PRIORITY, command.priority_level);
    write_register(reg_pkg::REG_CMD_ID, command.command_id);
    write_register(reg_pkg::REG_CMD_SUBMIT, register_mask(reg_pkg::CMD_SUBMIT_BIT));
  endtask

  function data_t register_mask(int unsigned index);
    data_t value = '0;
    value[index] = 1'b1;
    return value;
  endfunction

  task write_register(logic [AXIL_ADDR_WIDTH-1:0] address, data_t value);
    axil_item request = axil_item::type_id::create("request");
    start_item(request);
    request.direction = axil_item::AXIL_WRITE;
    request.address = address;
    request.write_data = value;
    request.write_strobe = '1;
    finish_item(request);
    if (request.response != AXIL_RESP_OKAY) begin
      `uvm_fatal(get_type_name(), $sformatf("Command register write failed at 0x%03x", address))
    end
  endtask
endclass

class soc_command_sequence_library extends uvm_sequence_library #(axil_item);
  `uvm_object_utils(soc_command_sequence_library)
  `uvm_sequence_library_utils(soc_command_sequence_library)

  function new(string name = "soc_command_sequence_library");
    super.new(name);
    init_sequence_library();
    add_typewide_sequence(soc_command_program_sequence::get_type());
  endfunction
endclass
