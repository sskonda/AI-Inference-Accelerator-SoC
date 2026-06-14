module soc_timer #(
    parameter int unsigned TIMER_WIDTH = reg_pkg::TIMER_INTERVAL_WIDTH
) (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   enable,
  input  logic                   periodic,
  input  logic [TIMER_WIDTH-1:0] interval,
  output logic [TIMER_WIDTH-1:0] value,
  output logic                   tick,
  output logic                   active
);

  logic                   previous_enable;
  logic                   previous_periodic;
  logic [TIMER_WIDTH-1:0] previous_interval;
  logic                   armed;
  logic                   configuration_changed;

  initial begin : validate_parameters
    if (TIMER_WIDTH == 0) begin
      $fatal(1, "Timer width must be positive");
    end
  end

  always_comb begin
    configuration_changed = (enable != previous_enable) || (periodic != previous_periodic) ||
        (interval != previous_interval);
    active = enable && armed;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      previous_enable <= 1'b0;
      previous_periodic <= 1'b0;
      previous_interval <= '0;
      value <= '0;
      tick <= 1'b0;
      armed <= 1'b0;
    end else begin
      previous_enable <= enable;
      previous_periodic <= periodic;
      previous_interval <= interval;
      tick <= 1'b0;

      if (!enable) begin
        value <= '0;
        armed <= 1'b0;
      end else if (configuration_changed) begin
        value <= '0;
        armed <= interval != '0;
      end else if (armed) begin
        if (value == (interval - 1'b1)) begin
          tick <= 1'b1;
          if (periodic) begin
            value <= '0;
          end else begin
            armed <= 1'b0;
          end
        end else begin
          value <= value + 1'b1;
        end
      end
    end
  end

  property p_tick_has_expiration_cause;
    @(posedge clk) disable iff (!rst_n) tick |-> $past(
        enable && armed && (interval != '0) && (value == (interval - 1'b1))
    );
  endproperty

  property p_disable_clears_value;
    @(posedge clk) disable iff (!rst_n) $past(
        !enable
    ) |-> (value == '0) && !tick;
  endproperty

  property p_known_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {enable, periodic, interval, value, tick, active}
    );
  endproperty

  a_tick_has_expiration_cause :
  assert property (p_tick_has_expiration_cause);
  a_disable_clears_value :
  assert property (p_disable_clears_value);
  a_known_control :
  assert property (p_known_control);

endmodule
