module irq_controller #(
    parameter int unsigned SOURCE_COUNT  = soc_pkg::IRQ_SOURCE_COUNT,
    parameter int unsigned LATENCY_WIDTH = soc_pkg::DATA_WIDTH
) (
  input  logic                     clk,
  input  logic                     rst_n,
  input  logic [ SOURCE_COUNT-1:0] sources,
  input  logic [ SOURCE_COUNT-1:0] enable,
  input  logic [ SOURCE_COUNT-1:0] clear,
  output logic [ SOURCE_COUNT-1:0] pending,
  output logic                     irq,
  output logic                     service_latency_valid,
  output logic [LATENCY_WIDTH-1:0] service_latency_cycles
);

  localparam logic [LATENCY_WIDTH-1:0] MAX_LATENCY = '1;

  logic [ SOURCE_COUNT-1:0] next_pending;
  logic                     service_event;
  logic                     next_irq;
  logic                     latency_tracking;
  logic [LATENCY_WIDTH-1:0] latency_counter;

  initial begin : validate_parameters
    if ((SOURCE_COUNT == 0) || (LATENCY_WIDTH == 0)) begin
      $fatal(1, "Interrupt source count and latency width must be positive");
    end
  end

  always_comb begin
    next_pending = (pending & ~clear) | sources;
    irq = |(pending & enable);
    next_irq = |(next_pending & enable);
    service_event = |(pending & enable & clear);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pending <= '0;
    end else begin
      pending <= next_pending;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      service_latency_valid <= 1'b0;
      service_latency_cycles <= '0;
      latency_tracking <= 1'b0;
      latency_counter <= '0;
    end else begin
      service_latency_valid <= 1'b0;

      if (service_event) begin
        service_latency_valid <= 1'b1;
        service_latency_cycles <= latency_counter;
        latency_counter <= '0;
        latency_tracking <= next_irq;
      end else if (!irq) begin
        latency_counter  <= '0;
        latency_tracking <= 1'b0;
      end else if (!latency_tracking) begin
        latency_counter  <= '0;
        latency_tracking <= 1'b1;
      end else if (latency_counter != MAX_LATENCY) begin
        latency_counter <= latency_counter + 1'b1;
      end
    end
  end

  for (genvar source_index = 0; source_index < SOURCE_COUNT; source_index++) begin : gen_assertions
    property p_pending_persists_without_clear;
      @(posedge clk) disable iff (!rst_n) pending[source_index] &&
          !clear[source_index] |=> pending[source_index];
    endproperty

    property p_source_wins_clear;
      @(posedge clk) disable iff (!rst_n) sources[source_index] |=> pending[source_index];
    endproperty

    a_pending_persists_without_clear :
    assert property (p_pending_persists_without_clear);
    a_source_wins_clear :
    assert property (p_source_wins_clear);
  end

  property p_disabled_pending_does_not_assert;
    @(posedge clk) disable iff (!rst_n) ((pending & enable) == '0) |-> !irq;
  endproperty

  property p_enabled_pending_asserts;
    @(posedge clk) disable iff (!rst_n) ((pending & enable) != '0) |-> irq;
  endproperty

  property p_latency_valid_follows_service;
    @(posedge clk) disable iff (!rst_n) service_latency_valid |-> $past(
        service_event
    );
  endproperty

  property p_known_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {sources, enable, clear, pending, irq, service_latency_valid, service_latency_cycles}
    );
  endproperty

  a_disabled_pending_does_not_assert :
  assert property (p_disabled_pending_does_not_assert);
  a_enabled_pending_asserts :
  assert property (p_enabled_pending_asserts);
  a_latency_valid_follows_service :
  assert property (p_latency_valid_follows_service);
  a_known_control :
  assert property (p_known_control);

endmodule
