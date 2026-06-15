class soc_memory_model extends uvm_object;
  byte unsigned storage[addr_t];

  `uvm_object_utils(soc_memory_model)

  function new(string name = "soc_memory_model");
    super.new(name);
  endfunction

  function bit address_is_legal(addr_t address);
    return data_range_is_legal(address, byte_count_t'(DATA_BYTES)) && is_dram_address(address);
  endfunction

  function data_t read_word(addr_t address);
    data_t value = '0;
    for (int unsigned byte_index = 0; byte_index < DATA_BYTES; byte_index++) begin
      addr_t byte_address = address + addr_t'(byte_index);
      if (storage.exists(byte_address)) begin
        value[byte_index*BITS_PER_BYTE+:BITS_PER_BYTE] = storage[byte_address];
      end
    end
    return value;
  endfunction

  function void write_word(addr_t address, data_t value, strb_t strobe);
    for (int unsigned byte_index = 0; byte_index < DATA_BYTES; byte_index++) begin
      if (strobe[byte_index]) begin
        storage[address+addr_t'(byte_index)] = value[byte_index*BITS_PER_BYTE+:BITS_PER_BYTE];
      end
    end
  endfunction

  function void write_bytes(addr_t address, input byte unsigned values[]);
    foreach (values[index]) begin
      storage[address+addr_t'(index)] = values[index];
    end
  endfunction

  function void read_bytes(addr_t address, int unsigned count, output byte unsigned values[]);
    values = new[count];
    foreach (values[index]) begin
      addr_t byte_address = address + addr_t'(index);
      values[index] = storage.exists(byte_address) ? storage[byte_address] : '0;
    end
  endfunction

  function void clear();
    storage.delete();
  endfunction
endclass
