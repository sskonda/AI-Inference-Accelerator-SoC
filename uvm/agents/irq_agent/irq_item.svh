class irq_item extends uvm_sequence_item;
  bit asserted;
  longint unsigned cycle;

  `uvm_object_utils_begin(irq_item)
    `uvm_field_int(asserted, UVM_DEFAULT)
    `uvm_field_int(cycle, UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "irq_item");
    super.new(name);
  endfunction
endclass
