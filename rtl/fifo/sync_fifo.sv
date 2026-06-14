module sync_fifo #(
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH,
    parameter int unsigned DEPTH = soc_pkg::DEFAULT_FIFO_DEPTH,
    parameter int unsigned COUNT_WIDTH = soc_pkg::width_for_count(DEPTH)
) (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   push_valid,
  output logic                   push_ready,
  input  logic [ DATA_WIDTH-1:0] push_data,
  output logic                   pop_valid,
  input  logic                   pop_ready,
  output logic [ DATA_WIDTH-1:0] pop_data,
  output logic                   full,
  output logic                   empty,
  output logic [COUNT_WIDTH-1:0] occupancy
);

  localparam int unsigned POINTER_WIDTH = soc_pkg::width_for_index(DEPTH);
  localparam logic [POINTER_WIDTH-1:0] LAST_POINTER = POINTER_WIDTH'(DEPTH - 1);

  logic [   DATA_WIDTH-1:0] storage       [DEPTH];
  logic [POINTER_WIDTH-1:0] read_pointer;
  logic [POINTER_WIDTH-1:0] write_pointer;
  logic                     push_fire;
  logic                     pop_fire;

  function automatic logic [POINTER_WIDTH-1:0] increment_pointer(
      input logic [POINTER_WIDTH-1:0] pointer);
    if (pointer == LAST_POINTER) begin
      return '0;
    end
    return pointer + 1'b1;
  endfunction

  initial begin : validate_parameters
    if ((DATA_WIDTH == 0) || (DEPTH == 0)) begin
      $fatal(1, "FIFO data width and depth must be positive");
    end
    if (COUNT_WIDTH != soc_pkg::width_for_count(DEPTH)) begin
      $fatal(1, "FIFO count width does not match depth");
    end
  end

  always_comb begin
    full = occupancy == COUNT_WIDTH'(DEPTH);
    empty = occupancy == '0;
    pop_valid = !empty;
    pop_data = storage[read_pointer];
    push_ready = !full || (pop_valid && pop_ready);
    push_fire = push_valid && push_ready;
    pop_fire = pop_valid && pop_ready;
  end

  always_ff @(posedge clk) begin
    if (push_fire) begin
      storage[write_pointer] <= push_data;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      read_pointer <= '0;
      write_pointer <= '0;
      occupancy <= '0;
    end else begin
      if (push_fire) begin
        write_pointer <= increment_pointer(write_pointer);
      end
      if (pop_fire) begin
        read_pointer <= increment_pointer(read_pointer);
      end

      unique case ({
        push_fire, pop_fire
      })
        2'b10:   occupancy <= occupancy + 1'b1;
        2'b01:   occupancy <= occupancy - 1'b1;
        default: occupancy <= occupancy;
      endcase
    end
  end

  property p_input_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) push_valid && !push_ready |=> push_valid && $stable(
        push_data
    );
  endproperty

  property p_output_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) pop_valid && !pop_ready |=> pop_valid && $stable(
        pop_data
    );
  endproperty

  property p_no_overflow;
    @(posedge clk) disable iff (!rst_n) push_fire |-> !full || pop_fire;
  endproperty

  property p_no_underflow;
    @(posedge clk) disable iff (!rst_n) pop_fire |-> !empty;
  endproperty

  property p_occupancy_in_range;
    @(posedge clk) disable iff (!rst_n) occupancy <= COUNT_WIDTH'(DEPTH);
  endproperty

  property p_reset_clears_control;
    @(posedge clk) !rst_n |=> empty && !full && (occupancy == '0);
  endproperty

  a_input_stable_while_stalled :
  assert property (p_input_stable_while_stalled);
  a_output_stable_while_stalled :
  assert property (p_output_stable_while_stalled);
  a_no_overflow :
  assert property (p_no_overflow);
  a_no_underflow :
  assert property (p_no_underflow);
  a_occupancy_in_range :
  assert property (p_occupancy_in_range);
  a_reset_clears_control :
  assert property (p_reset_clears_control);

endmodule
