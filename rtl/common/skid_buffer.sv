module skid_buffer #(
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  input_valid,
  output logic                  input_ready,
  input  logic [DATA_WIDTH-1:0] input_data,
  output logic                  output_valid,
  input  logic                  output_ready,
  output logic [DATA_WIDTH-1:0] output_data
);

  logic                  buffer_valid;
  logic [DATA_WIDTH-1:0] buffer_data;

  initial begin : validate_parameters
    if (DATA_WIDTH == 0) begin
      $fatal(1, "Skid-buffer data width must be positive");
    end
  end

  always_comb begin
    input_ready  = !buffer_valid || output_ready;
    output_valid = buffer_valid || input_valid;
    output_data  = buffer_valid ? buffer_data : input_data;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      buffer_valid <= 1'b0;
    end else if (buffer_valid) begin
      if (output_ready) begin
        buffer_valid <= input_valid;
      end
    end else begin
      buffer_valid <= input_valid && !output_ready;
    end
  end

  always_ff @(posedge clk) begin
    if (input_valid && input_ready && (buffer_valid || !output_ready)) begin
      buffer_data <= input_data;
    end
  end

  property p_input_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) input_valid && !input_ready |=> input_valid && $stable(
        input_data
    );
  endproperty

  property p_output_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) output_valid && !output_ready |=> output_valid && $stable(
        output_data
    );
  endproperty

  property p_reset_clears_valid;
    @(posedge clk) $rose(
        rst_n
    ) |-> !$past(
        buffer_valid
    );
  endproperty

  a_input_stable_while_stalled :
  assert property (p_input_stable_while_stalled);
  a_output_stable_while_stalled :
  assert property (p_output_stable_while_stalled);
  a_reset_clears_valid :
  assert property (p_reset_clears_valid);

endmodule
