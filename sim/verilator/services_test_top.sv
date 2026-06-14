module services_test_top #(
    parameter int unsigned TIMER_WIDTH = 8,
    parameter int unsigned TEST_COUNTER_WIDTH = 8,
    parameter int unsigned IRQ_LATENCY_WIDTH = 8
) (
  input logic clk,
  input logic rst_n,

  input  logic                   timer_enable,
  input  logic                   timer_periodic,
  input  logic [TIMER_WIDTH-1:0] timer_interval,
  output logic [TIMER_WIDTH-1:0] timer_value,
  output logic                   timer_tick,
  output logic                   timer_active,

  input  logic [soc_pkg::IRQ_SOURCE_COUNT-1:0] irq_sources,
  input  logic [soc_pkg::IRQ_SOURCE_COUNT-1:0] irq_enable,
  input  logic [soc_pkg::IRQ_SOURCE_COUNT-1:0] irq_clear,
  output logic [soc_pkg::IRQ_SOURCE_COUNT-1:0] irq_pending,
  output logic                                 irq,
  output logic                                 irq_latency_valid,
  output logic [        IRQ_LATENCY_WIDTH-1:0] irq_latency_cycles,

  input  logic                                      perf_clear,
  input  logic                                      dma_active,
  input  logic                                      dma_stalled,
  input  logic                                      accel_active,
  input  logic                                      accel_stalled,
  input  logic [reg_pkg::QUEUE_OCCUPANCY_WIDTH-1:0] queue_occupancy,
  input  logic                                      command_completed,
  input  logic [     soc_pkg::BYTE_COUNT_WIDTH-1:0] bytes_read,
  input  logic [     soc_pkg::BYTE_COUNT_WIDTH-1:0] bytes_written,
  input  logic                                      perf_irq_latency_valid,
  input  logic [             IRQ_LATENCY_WIDTH-1:0] perf_irq_latency_cycles,
  input  logic                                      scheduler_stalled,
  input  logic [soc_pkg::PERF_COUNTER_ID_WIDTH-1:0] perf_select,
  output logic [            TEST_COUNTER_WIDTH-1:0] perf_value,

  output logic [soc_pkg::DATA_WIDTH-1:0] definition_checksum
);

  logic [soc_pkg::IRQ_SOURCE_COUNT-1:0] combined_sources;

  protocol_compile_top u_protocol_compile (
      .clk                (clk),
      .rst_n              (rst_n),
      .definition_checksum(definition_checksum)
  );

  always_comb begin
    combined_sources = irq_sources;
    combined_sources[soc_pkg::IRQ_TIMER_BIT] = timer_tick;
  end

  soc_timer #(
      .TIMER_WIDTH(TIMER_WIDTH)
  ) u_timer (
      .clk     (clk),
      .rst_n   (rst_n),
      .enable  (timer_enable),
      .periodic(timer_periodic),
      .interval(timer_interval),
      .value   (timer_value),
      .tick    (timer_tick),
      .active  (timer_active)
  );

  irq_controller #(
      .LATENCY_WIDTH(IRQ_LATENCY_WIDTH)
  ) u_irq_controller (
      .clk                   (clk),
      .rst_n                 (rst_n),
      .sources               (combined_sources),
      .enable                (irq_enable),
      .clear                 (irq_clear),
      .pending               (irq_pending),
      .irq                   (irq),
      .service_latency_valid (irq_latency_valid),
      .service_latency_cycles(irq_latency_cycles)
  );

  performance_counters #(
      .COUNTER_WIDTH(TEST_COUNTER_WIDTH),
      .LATENCY_WIDTH(IRQ_LATENCY_WIDTH)
  ) u_performance_counters (
      .clk               (clk),
      .rst_n             (rst_n),
      .clear             (perf_clear),
      .dma_active        (dma_active),
      .dma_stalled       (dma_stalled),
      .accel_active      (accel_active),
      .accel_stalled     (accel_stalled),
      .queue_occupancy   (queue_occupancy),
      .command_completed (command_completed),
      .bytes_read        (bytes_read),
      .bytes_written     (bytes_written),
      .irq_latency_valid (perf_irq_latency_valid),
      .irq_latency_cycles(perf_irq_latency_cycles),
      .scheduler_stalled (scheduler_stalled),
      .select            (soc_pkg::perf_counter_id_e'(perf_select)),
      .selected_value    (perf_value)
  );

endmodule
