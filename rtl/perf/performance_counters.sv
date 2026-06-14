module performance_counters #(
    parameter int unsigned COUNTER_WIDTH = soc_pkg::PERF_COUNTER_WIDTH,
    parameter int unsigned QUEUE_WIDTH   = reg_pkg::QUEUE_OCCUPANCY_WIDTH,
    parameter int unsigned LATENCY_WIDTH = soc_pkg::DATA_WIDTH
) (
  input logic clk,
  input logic rst_n,
  input logic clear,

  input logic                                     dma_active,
  input logic                                     dma_stalled,
  input logic                                     accel_active,
  input logic                                     accel_stalled,
  input logic                 [  QUEUE_WIDTH-1:0] queue_occupancy,
  input logic                                     command_completed,
  input soc_pkg::byte_count_t                     bytes_read,
  input soc_pkg::byte_count_t                     bytes_written,
  input logic                                     irq_latency_valid,
  input logic                 [LATENCY_WIDTH-1:0] irq_latency_cycles,
  input logic                                     scheduler_stalled,

  input  soc_pkg::perf_counter_id_e                     select,
  output logic                      [COUNTER_WIDTH-1:0] selected_value
);

  import soc_pkg::*;

  localparam int unsigned COUNTER_COUNT = 2 ** PERF_COUNTER_ID_WIDTH;
  localparam logic [COUNTER_WIDTH-1:0] COUNTER_MAX = '1;

  typedef logic [COUNTER_WIDTH-1:0] counter_t;

  counter_t counters[COUNTER_COUNT];

  function automatic counter_t saturating_add(input counter_t value, input counter_t increment);
    if (increment > (COUNTER_MAX - value)) begin
      return COUNTER_MAX;
    end
    return value + increment;
  endfunction

  initial begin : validate_parameters
    if ((COUNTER_WIDTH == 0) || (QUEUE_WIDTH == 0) || (LATENCY_WIDTH == 0)) begin
      $fatal(1, "Performance counter widths must be positive");
    end
  end

  always_comb begin
    selected_value = counters[PERF_COUNTER_ID_WIDTH'(select)];
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int unsigned counter_index = 0; counter_index < COUNTER_COUNT; counter_index++) begin
        counters[counter_index] <= '0;
      end
    end else if (clear) begin
      for (int unsigned counter_index = 0; counter_index < COUNTER_COUNT; counter_index++) begin
        counters[counter_index] <= '0;
      end
    end else begin
      counters[PERF_TOTAL_CYCLES] <= saturating_add(counters[PERF_TOTAL_CYCLES], counter_t'(1));
      if (dma_active) begin
        counters[PERF_DMA_ACTIVE_CYCLES] <=
            saturating_add(counters[PERF_DMA_ACTIVE_CYCLES], counter_t'(1));
      end
      if (dma_stalled) begin
        counters[PERF_DMA_STALLED_CYCLES] <=
            saturating_add(counters[PERF_DMA_STALLED_CYCLES], counter_t'(1));
      end
      if (accel_active) begin
        counters[PERF_ACCEL_ACTIVE_CYCLES] <=
            saturating_add(counters[PERF_ACCEL_ACTIVE_CYCLES], counter_t'(1));
      end
      if (accel_stalled) begin
        counters[PERF_ACCEL_STALLED_CYCLES] <=
            saturating_add(counters[PERF_ACCEL_STALLED_CYCLES], counter_t'(1));
      end
      if (counter_t'(queue_occupancy) > counters[PERF_QUEUE_HIGH_WATER]) begin
        counters[PERF_QUEUE_HIGH_WATER] <= counter_t'(queue_occupancy);
      end
      if (command_completed) begin
        counters[PERF_COMMANDS_COMPLETED] <=
            saturating_add(counters[PERF_COMMANDS_COMPLETED], counter_t'(1));
      end
      if (bytes_read != '0) begin
        counters[PERF_BYTES_READ] <=
            saturating_add(counters[PERF_BYTES_READ], counter_t'(bytes_read));
      end
      if (bytes_written != '0) begin
        counters[PERF_BYTES_WRITTEN] <=
            saturating_add(counters[PERF_BYTES_WRITTEN], counter_t'(bytes_written));
      end
      if (irq_latency_valid && (counter_t'(irq_latency_cycles) > counters[PERF_IRQ_LATENCY])) begin
        counters[PERF_IRQ_LATENCY] <= counter_t'(irq_latency_cycles);
      end
      if (scheduler_stalled) begin
        counters[PERF_SCHEDULER_STALLS] <=
            saturating_add(counters[PERF_SCHEDULER_STALLS], counter_t'(1));
      end
    end
  end

  for (
      genvar counter_index = 0; counter_index < COUNTER_COUNT; counter_index++
  ) begin : gen_counter_assertions
    property p_counter_known;
      @(posedge clk) disable iff (!rst_n) !$isunknown(
          counters[counter_index]
      );
    endproperty

    property p_clear_resets_counter;
      @(posedge clk) disable iff (!rst_n) clear |=> counters[counter_index] == '0;
    endproperty

    a_counter_known :
    assert property (p_counter_known);
    a_clear_resets_counter :
    assert property (p_clear_resets_counter);
  end

  property p_selected_value_known;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        selected_value
    );
  endproperty

  a_selected_value_known :
  assert property (p_selected_value_known);

endmodule
