interface irq_if #(
    parameter int unsigned SOURCE_COUNT = soc_pkg::IRQ_SOURCE_COUNT
) (
  input logic clk,
  input logic rst_n
);

  logic [SOURCE_COUNT-1:0] sources;
  logic [SOURCE_COUNT-1:0] pending;
  logic [SOURCE_COUNT-1:0] enable;
  logic [SOURCE_COUNT-1:0] clear;
  logic                    irq;

  initial begin : validate_parameters
    if (SOURCE_COUNT == 0) begin
      $fatal(1, "Interrupt source count must be positive");
    end
  end

  property p_known_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {sources, pending, enable, clear, irq}
    );
  endproperty

  property p_irq_matches_enabled_pending;
    @(posedge clk) disable iff (!rst_n) irq == (|(pending & enable));
  endproperty

  a_known_control :
  assert property (p_known_control);
  a_irq_matches_enabled_pending :
  assert property (p_irq_matches_enabled_pending);

  for (genvar source_index = 0; source_index < SOURCE_COUNT; source_index++) begin : gen_sticky
    property p_pending_sticky_without_clear;
      @(posedge clk) disable iff (!rst_n) pending[source_index] &&
          !clear[source_index] |=> pending[source_index];
    endproperty

    a_pending_sticky_without_clear :
    assert property (p_pending_sticky_without_clear);
  end

  modport source(output sources);

  modport controller(input sources, clear, output pending, enable, irq);

  modport monitor(input clk, rst_n, sources, pending, enable, clear, irq);

endinterface
