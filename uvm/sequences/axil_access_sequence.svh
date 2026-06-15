class axil_access_sequence extends uvm_sequence #(axil_item);
  `uvm_object_utils(axil_access_sequence)

  axil_item::direction_e direction;
  logic [AXIL_ADDR_WIDTH-1:0] address;
  data_t write_data;
  strb_t write_strobe = '1;
  data_t read_data;
  axil_resp_e response;

  function new(string name = "axil_access_sequence");
    super.new(name);
  endfunction

  task body();
    axil_item request = axil_item::type_id::create("request");
    start_item(request);
    request.direction = direction;
    request.address = address;
    request.write_data = write_data;
    request.write_strobe = write_strobe;
    finish_item(request);
    read_data = request.read_data;
    response  = request.response;
  endtask
endclass
