interface stream_if #(
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH,
    parameter int unsigned USER_WIDTH = soc_pkg::DEFAULT_STREAM_USER_WIDTH
) (
  input logic clk,
  input logic rst_n
);

  logic                  valid;
  logic                  ready;
  logic [DATA_WIDTH-1:0] data;
  logic                  last;
  logic [USER_WIDTH-1:0] user;

  initial begin : validate_parameters
    if ((DATA_WIDTH == 0) || (USER_WIDTH == 0)) begin
      $fatal(1, "Stream data and user widths must be positive");
    end
  end

  property p_payload_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) valid && !ready |=> valid && $stable(
        {data, last, user}
    );
  endproperty

  property p_known_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {valid, ready, last}
    );
  endproperty

  a_payload_stable_while_stalled :
  assert property (p_payload_stable_while_stalled);
  a_known_control :
  assert property (p_known_control);

  modport source(input ready, output valid, data, last, user);
  modport sink(input valid, data, last, user, output ready);
  modport monitor(input clk, rst_n, valid, ready, data, last, user);

endinterface
