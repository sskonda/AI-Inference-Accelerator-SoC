class axil_item extends uvm_sequence_item;
  typedef enum bit {
    AXIL_READ,
    AXIL_WRITE
  } direction_e;

  rand direction_e                       direction;
  rand logic       [AXIL_ADDR_WIDTH-1:0] address;
  rand logic       [     DATA_WIDTH-1:0] write_data;
  rand logic       [     STRB_WIDTH-1:0] write_strobe;
  logic            [     DATA_WIDTH-1:0] read_data;
  axil_resp_e                            response;

  constraint word_aligned_c {address[WORD_ADDRESS_LSB-1:0] == '0;}

  constraint write_strobe_c {
    if (direction == AXIL_WRITE) {
      write_strobe != '0;
    }
  }

  `uvm_object_utils_begin(axil_item)
    `uvm_field_enum(direction_e, direction, UVM_DEFAULT)
    `uvm_field_int(address, UVM_HEX)
    `uvm_field_int(write_data, UVM_HEX)
    `uvm_field_int(write_strobe, UVM_HEX)
    `uvm_field_int(read_data, UVM_HEX)
    `uvm_field_enum(axil_resp_e, response, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "axil_item");
    super.new(name);
  endfunction
endclass
