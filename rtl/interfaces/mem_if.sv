interface mem_if #(
    parameter int unsigned ADDR_WIDTH = soc_pkg::ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH
) (
  input logic clk,
  input logic rst_n
);

  localparam int unsigned STRB_WIDTH = DATA_WIDTH / soc_pkg::BITS_PER_BYTE;

  logic                  req_valid;
  logic                  req_ready;
  logic                  req_write;
  logic [ADDR_WIDTH-1:0] req_addr;
  logic [DATA_WIDTH-1:0] req_wdata;
  logic [STRB_WIDTH-1:0] req_wstrb;

  logic                  rsp_valid;
  logic                  rsp_ready;
  logic [DATA_WIDTH-1:0] rsp_rdata;
  logic                  rsp_error;

  initial begin : validate_parameters
    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % soc_pkg::BITS_PER_BYTE) != 0)) begin
      $fatal(1, "Memory data width must contain a positive whole number of bytes");
    end
    if (ADDR_WIDTH == 0) begin
      $fatal(1, "Memory address width must be positive");
    end
  end

  property p_request_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) req_valid && !req_ready |=> req_valid && $stable(
        {req_write, req_addr, req_wdata, req_wstrb}
    );
  endproperty

  property p_response_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) rsp_valid && !rsp_ready |=> rsp_valid && $stable(
        {rsp_rdata, rsp_error}
    );
  endproperty

  property p_known_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {req_valid, req_ready, req_write, rsp_valid, rsp_ready, rsp_error}
    );
  endproperty

  property p_write_has_byte_enable;
    @(posedge clk) disable iff (!rst_n) req_valid && req_ready && req_write |-> (req_wstrb != '0);
  endproperty

  a_request_stable_while_stalled :
  assert property (p_request_stable_while_stalled);
  a_response_stable_while_stalled :
  assert property (p_response_stable_while_stalled);
  a_known_control :
  assert property (p_known_control);
  a_write_has_byte_enable :
  assert property (p_write_has_byte_enable);

  modport initiator(
      input req_ready, rsp_valid, rsp_rdata, rsp_error,
      output req_valid, req_write, req_addr, req_wdata, req_wstrb, rsp_ready
  );

  modport target(
      input req_valid, req_write, req_addr, req_wdata, req_wstrb, rsp_ready,
      output req_ready, rsp_valid, rsp_rdata, rsp_error
  );

  modport monitor(
      input clk, rst_n, req_valid, req_ready, req_write, req_addr, req_wdata, req_wstrb, rsp_valid,
          rsp_ready, rsp_rdata, rsp_error
  );

endinterface
