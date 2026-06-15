class mem_item extends uvm_sequence_item;
  addr_t           address;
  mem_direction_e  direction;
  data_t           write_data;
  strb_t           write_strobe;
  bit              last;
  data_t           read_data;
  bit              error;
  longint unsigned request_cycle;
  longint unsigned response_cycle;

  `uvm_object_utils_begin(mem_item)
    `uvm_field_int(address, UVM_HEX)
    `uvm_field_enum(mem_direction_e, direction, UVM_DEFAULT)
    `uvm_field_int(write_data, UVM_HEX)
    `uvm_field_int(write_strobe, UVM_HEX)
    `uvm_field_int(last, UVM_DEFAULT)
    `uvm_field_int(read_data, UVM_HEX)
    `uvm_field_int(error, UVM_DEFAULT)
    `uvm_field_int(request_cycle, UVM_DEC)
    `uvm_field_int(response_cycle, UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "mem_item");
    super.new(name);
  endfunction
endclass
