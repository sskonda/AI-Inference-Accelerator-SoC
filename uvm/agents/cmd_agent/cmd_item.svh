class cmd_item extends uvm_sequence_item;
  logic [COMMAND_ID_WIDTH-1:0] command_id;
  command_opcode_e opcode;
  bit error;
  int unsigned queue_occupancy;
  longint unsigned cycle;

  `uvm_object_utils_begin(cmd_item)
    `uvm_field_int(command_id, UVM_HEX)
    `uvm_field_enum(command_opcode_e, opcode, UVM_DEFAULT)
    `uvm_field_int(error, UVM_DEFAULT)
    `uvm_field_int(queue_occupancy, UVM_DEC)
    `uvm_field_int(cycle, UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "cmd_item");
    super.new(name);
  endfunction
endclass
