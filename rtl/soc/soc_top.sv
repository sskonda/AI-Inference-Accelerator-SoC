module soc_top (
  input logic clk,
  input logic rst_n,

  input  logic                                axil_awvalid,
  output logic                                axil_awready,
  input  logic [soc_pkg::AXIL_ADDR_WIDTH-1:0] axil_awaddr,
  input  logic                                axil_wvalid,
  output logic                                axil_wready,
  input  logic [     soc_pkg::DATA_WIDTH-1:0] axil_wdata,
  input  logic [     soc_pkg::STRB_WIDTH-1:0] axil_wstrb,
  output logic                                axil_bvalid,
  input  logic                                axil_bready,
  output logic [soc_pkg::AXIL_RESP_WIDTH-1:0] axil_bresp,
  input  logic                                axil_arvalid,
  output logic                                axil_arready,
  input  logic [soc_pkg::AXIL_ADDR_WIDTH-1:0] axil_araddr,
  output logic                                axil_rvalid,
  input  logic                                axil_rready,
  output logic [     soc_pkg::DATA_WIDTH-1:0] axil_rdata,
  output logic [soc_pkg::AXIL_RESP_WIDTH-1:0] axil_rresp,

  output logic                           memory_req_valid,
  input  logic                           memory_req_ready,
  output logic                           memory_req_write,
  output logic [soc_pkg::ADDR_WIDTH-1:0] memory_req_addr,
  output logic [soc_pkg::DATA_WIDTH-1:0] memory_req_wdata,
  output logic [soc_pkg::STRB_WIDTH-1:0] memory_req_wstrb,
  output logic                           memory_req_last,
  input  logic                           memory_rsp_valid,
  output logic                           memory_rsp_ready,
  input  logic [soc_pkg::DATA_WIDTH-1:0] memory_rsp_rdata,
  input  logic                           memory_rsp_error,

  output logic                                      irq,
  output logic                                      soc_busy,
  output logic                                      debug_dma_done,
  output logic                                      debug_command_completed,
  output logic                                      debug_accelerator_done,
  output logic                                      debug_fabric_busy,
  output logic [reg_pkg::QUEUE_OCCUPANCY_WIDTH-1:0] debug_queue_occupancy,
  output logic [   soc_pkg::ERROR_STATUS_WIDTH-1:0] debug_error_status,
  output logic [           soc_pkg::DATA_WIDTH-1:0] debug_definition_checksum
);

  import accel_pkg::*;
  import reg_pkg::*;
  import soc_pkg::*;

  localparam int unsigned QUEUE_COUNT_WIDTH = width_for_count(DEFAULT_COMMAND_QUEUE_DEPTH);
  localparam int unsigned ERROR_INDEX_WIDTH = width_for_index(ERROR_STATUS_WIDTH);
  localparam data_t DEFINITION_CHECKSUM = data_t'(DEFAULT_STARVATION_THRESHOLD) ^ data_t
      '(FLAG_IRQ_ON_DONE_BIT) ^ data_t'(DEFAULT_STREAM_USER_WIDTH) ^ data_t'(DEFAULT_FIFO_DEPTH);

  axil_if control_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );
  cmd_if command_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  mem_if dma_source_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );
  mem_if dma_destination_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );
  mem_if vector_memory_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );
  mem_if reduction_memory_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );
  mem_if gemm_memory_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );
  mem_if external_memory_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  logic                                             global_enable;
  logic                                             perf_clear;
  logic                                             scheduler_priority_mode;
  logic              [STARVATION_COUNTER_WIDTH-1:0] scheduler_starvation_threshold;
  scheduler_policy_e                                scheduler_policy;

  logic              [        IRQ_SOURCE_COUNT-1:0] irq_sources;
  logic              [        IRQ_SOURCE_COUNT-1:0] irq_pending;
  logic              [        IRQ_SOURCE_COUNT-1:0] irq_enable;
  logic              [        IRQ_SOURCE_COUNT-1:0] irq_clear;
  logic                                             irq_latency_valid;
  logic              [              DATA_WIDTH-1:0] irq_latency_cycles;

  logic                                             timer_enable;
  logic                                             timer_periodic;
  logic              [    TIMER_INTERVAL_WIDTH-1:0] timer_interval;
  logic              [    TIMER_INTERVAL_WIDTH-1:0] timer_value;
  data_t                                            timer_value_register;
  logic                                             timer_tick;
  logic                                             timer_active;

  logic                                             mmio_dma_start;
  logic                                             dma_irq_enable;
  addr_t                                            mmio_dma_source_address;
  addr_t                                            mmio_dma_destination_address;
  byte_count_t                                      mmio_dma_length_bytes;
  logic                                             dma_engine_start;
  addr_t                                            dma_engine_source_address;
  addr_t                                            dma_engine_destination_address;
  byte_count_t                                      dma_engine_length_bytes;
  logic                                             dma_start_accepted;
  logic                                             dma_start_rejected;
  logic                                             dma_busy;
  logic                                             dma_done;
  logic                                             dma_error;
  error_e                                           dma_error_code;
  logic                                             dma_active_cycle;
  logic                                             dma_stalled_cycle;
  byte_count_t                                      dma_bytes_read;
  byte_count_t                                      dma_bytes_written;

  logic                                             queue_push_ready;
  logic                                             queue_pop_valid;
  logic                                             queue_pop_ready;
  command_desc_t                                    queue_pop_command;
  logic                                             queue_selected_starved;
  logic                                             queue_full;
  logic                                             queue_empty;
  logic              [       QUEUE_COUNT_WIDTH-1:0] queue_occupancy;
  logic              [       QUEUE_COUNT_WIDTH-1:0] queue_high_water;
  logic              [   QUEUE_OCCUPANCY_WIDTH-1:0] queue_occupancy_register;
  logic              [  QUEUE_HIGH_WATER_WIDTH-1:0] queue_high_water_register;

  logic                                             dma_command_valid;
  logic                                             dma_command_ready;
  command_desc_t                                    dma_command;
  logic                                             dma_response_valid;
  logic                                             dma_response_ready;
  command_response_t                                dma_response;

  logic                                             vector_command_valid;
  logic                                             vector_command_ready;
  command_desc_t                                    vector_command;
  logic                                             vector_response_valid;
  logic                                             vector_response_ready;
  command_response_t                                vector_response;

  logic                                             reduction_command_valid;
  logic                                             reduction_command_ready;
  command_desc_t                                    reduction_command;
  logic                                             reduction_response_valid;
  logic                                             reduction_response_ready;
  command_response_t                                reduction_response;

  logic                                             gemm_command_valid;
  logic                                             gemm_command_ready;
  command_desc_t                                    gemm_command;
  logic                                             gemm_response_valid;
  logic                                             gemm_response_ready;
  command_response_t                                gemm_response;

  logic                                             processor_response_valid;
  logic                                             processor_response_ready;
  command_response_t                                processor_response;
  logic                                             processor_busy;
  logic                                             scheduler_stalled;
  logic                                             command_completed;
  logic                                             command_error;

  logic                                             vector_busy;
  logic                                             vector_done;
  logic                                             vector_error;
  error_e                                           vector_error_code;
  logic                                             vector_active_cycle;
  logic                                             vector_stalled_cycle;
  logic              [            LENGTH_WIDTH-1:0] vector_elements_completed;

  logic                                             reduction_busy;
  logic                                             reduction_done;
  logic                                             reduction_error;
  error_e                                           reduction_error_code;
  logic                                             reduction_active_cycle;
  logic                                             reduction_stalled_cycle;
  logic              [            LENGTH_WIDTH-1:0] reduction_elements_completed;

  logic                                             gemm_busy;
  logic                                             gemm_done;
  logic                                             gemm_error;
  error_e                                           gemm_error_code;
  logic                                             gemm_active_cycle;
  logic                                             gemm_stalled_cycle;
  logic              [            LENGTH_WIDTH-1:0] gemm_outputs_completed;

  logic                                             accelerator_active;
  logic                                             accelerator_stalled;
  logic                                             accelerator_done;
  logic                                             fabric_busy;
  logic                                             fabric_error_event;
  perf_counter_id_e                                 perf_select;
  logic              [      PERF_COUNTER_WIDTH-1:0] perf_value;
  logic              [      ERROR_STATUS_WIDTH-1:0] hardware_error_set;
  logic              [      ERROR_STATUS_WIDTH-1:0] error_status;

  function automatic logic [ERROR_STATUS_WIDTH-1:0] error_code_mask(input error_e code);
    logic [ERROR_STATUS_WIDTH-1:0] mask;

    mask = '0;
    if (code != ERR_NONE) begin
      mask[ERROR_INDEX_WIDTH'(code)] = 1'b1;
    end
    return mask;
  endfunction

  assign control_bus.awvalid = axil_awvalid;
  assign axil_awready = control_bus.awready;
  assign control_bus.awaddr = axil_awaddr;
  assign control_bus.wvalid = axil_wvalid;
  assign axil_wready = control_bus.wready;
  assign control_bus.wdata = axil_wdata;
  assign control_bus.wstrb = axil_wstrb;
  assign axil_bvalid = control_bus.bvalid;
  assign control_bus.bready = axil_bready;
  assign axil_bresp = control_bus.bresp;
  assign control_bus.arvalid = axil_arvalid;
  assign axil_arready = control_bus.arready;
  assign control_bus.araddr = axil_araddr;
  assign axil_rvalid = control_bus.rvalid;
  assign control_bus.rready = axil_rready;
  assign axil_rdata = control_bus.rdata;
  assign axil_rresp = control_bus.rresp;

  assign memory_req_valid = external_memory_bus.req_valid;
  assign external_memory_bus.req_ready = memory_req_ready;
  assign memory_req_write = external_memory_bus.req_write;
  assign memory_req_addr = external_memory_bus.req_addr;
  assign memory_req_wdata = external_memory_bus.req_wdata;
  assign memory_req_wstrb = external_memory_bus.req_wstrb;
  assign memory_req_last = external_memory_bus.req_last;
  assign external_memory_bus.rsp_valid = memory_rsp_valid;
  assign memory_rsp_ready = external_memory_bus.rsp_ready;
  assign external_memory_bus.rsp_rdata = memory_rsp_rdata;
  assign external_memory_bus.rsp_error = memory_rsp_error;

  assign scheduler_policy = scheduler_priority_mode ? SCHED_PRIORITY_FIRST : SCHED_ROUND_ROBIN;
  assign timer_value_register = DATA_WIDTH'(timer_value);
  assign queue_occupancy_register = QUEUE_OCCUPANCY_WIDTH'(queue_occupancy);
  assign queue_high_water_register = QUEUE_HIGH_WATER_WIDTH'(queue_high_water);

  assign command_bus.cmd_ready = queue_push_ready;
  assign command_bus.cmd_full = queue_full;
  assign command_bus.rsp_valid = processor_response_valid;
  assign command_bus.rsp = processor_response;
  assign command_bus.rsp_empty = !processor_response_valid;
  assign processor_response_ready = command_bus.rsp_ready;

  assign accelerator_active = vector_active_cycle || reduction_active_cycle || gemm_active_cycle;
  assign
      accelerator_stalled = vector_stalled_cycle || reduction_stalled_cycle || gemm_stalled_cycle;
  assign accelerator_done = vector_done || reduction_done || gemm_done;

  always_comb begin
    irq_sources = '0;
    irq_sources[IRQ_DMA_DONE_BIT] = dma_done && dma_irq_enable;
    irq_sources[IRQ_CMD_DONE_BIT] = command_completed;
    irq_sources[IRQ_ACCEL_DONE_BIT] = accelerator_done;
    irq_sources[IRQ_ERROR_BIT] = dma_error || command_error || vector_error || reduction_error ||
        gemm_error || fabric_error_event;
    irq_sources[IRQ_TIMER_BIT] = timer_tick;
  end

  always_comb begin
    hardware_error_set = '0;
    if (dma_error) begin
      hardware_error_set |= error_code_mask(dma_error_code);
    end
    if (vector_error) begin
      hardware_error_set |= error_code_mask(vector_error_code);
    end
    if (reduction_error) begin
      hardware_error_set |= error_code_mask(reduction_error_code);
    end
    if (gemm_error) begin
      hardware_error_set |= error_code_mask(gemm_error_code);
    end
    if (fabric_error_event) begin
      hardware_error_set |= error_code_mask(ERR_ADDRESS);
    end
    if (command_error) begin
      hardware_error_set |= error_code_mask(ERR_INTERNAL);
    end
  end

  assign soc_busy = dma_busy || processor_busy || !queue_empty || vector_busy || reduction_busy ||
      gemm_busy || fabric_busy;
  assign debug_dma_done = dma_done;
  assign debug_command_completed = command_completed;
  assign debug_accelerator_done = accelerator_done;
  assign debug_fabric_busy = fabric_busy;
  assign debug_queue_occupancy = queue_occupancy_register;
  assign debug_error_status = error_status;
  assign debug_definition_checksum = DEFINITION_CHECKSUM;

  soc_register_block u_register_block (
      .clk                           (clk),
      .rst_n                         (rst_n),
      .axil                          (control_bus),
      .command_port                  (command_bus),
      .soc_busy                      (soc_busy),
      .global_enable                 (global_enable),
      .perf_clear                    (perf_clear),
      .scheduler_priority_mode       (scheduler_priority_mode),
      .scheduler_starvation_threshold(scheduler_starvation_threshold),
      .irq_pending                   (irq_pending),
      .irq_enable                    (irq_enable),
      .irq_clear                     (irq_clear),
      .timer_value                   (timer_value_register),
      .timer_enable                  (timer_enable),
      .timer_periodic                (timer_periodic),
      .timer_interval                (timer_interval),
      .dma_busy                      (dma_busy),
      .dma_done                      (dma_done),
      .dma_error                     (dma_error),
      .dma_start                     (mmio_dma_start),
      .dma_irq_enable                (dma_irq_enable),
      .dma_src_addr                  (mmio_dma_source_address),
      .dma_dst_addr                  (mmio_dma_destination_address),
      .dma_length_bytes              (mmio_dma_length_bytes),
      .queue_full                    (queue_full),
      .queue_empty                   (queue_empty),
      .queue_occupancy               (queue_occupancy_register),
      .queue_high_water              (queue_high_water_register),
      .perf_select                   (perf_select),
      .perf_value                    (perf_value),
      .hardware_error_set            (hardware_error_set),
      .error_status                  (error_status)
  );

  command_queue u_command_queue (
      .clk                 (clk),
      .rst_n               (rst_n),
      .push_valid          (command_bus.cmd_valid),
      .push_ready          (queue_push_ready),
      .push_command        (command_bus.cmd),
      .select_enable       (global_enable),
      .policy              (scheduler_policy),
      .starvation_threshold(scheduler_starvation_threshold),
      .pop_valid           (queue_pop_valid),
      .pop_ready           (queue_pop_ready),
      .pop_command         (queue_pop_command),
      .selected_starved    (queue_selected_starved),
      .full                (queue_full),
      .empty               (queue_empty),
      .occupancy           (queue_occupancy),
      .high_water          (queue_high_water)
  );

  command_processor u_command_processor (
      .clk                (clk),
      .rst_n              (rst_n),
      .execution_enable   (global_enable),
      .queue_valid        (queue_pop_valid),
      .queue_ready        (queue_pop_ready),
      .queue_command      (queue_pop_command),
      .dma_cmd_valid      (dma_command_valid),
      .dma_cmd_ready      (dma_command_ready),
      .dma_cmd            (dma_command),
      .dma_rsp_valid      (dma_response_valid),
      .dma_rsp_ready      (dma_response_ready),
      .dma_rsp            (dma_response),
      .vector_cmd_valid   (vector_command_valid),
      .vector_cmd_ready   (vector_command_ready),
      .vector_cmd         (vector_command),
      .vector_rsp_valid   (vector_response_valid),
      .vector_rsp_ready   (vector_response_ready),
      .vector_rsp         (vector_response),
      .reduction_cmd_valid(reduction_command_valid),
      .reduction_cmd_ready(reduction_command_ready),
      .reduction_cmd      (reduction_command),
      .reduction_rsp_valid(reduction_response_valid),
      .reduction_rsp_ready(reduction_response_ready),
      .reduction_rsp      (reduction_response),
      .gemm_cmd_valid     (gemm_command_valid),
      .gemm_cmd_ready     (gemm_command_ready),
      .gemm_cmd           (gemm_command),
      .gemm_rsp_valid     (gemm_response_valid),
      .gemm_rsp_ready     (gemm_response_ready),
      .gemm_rsp           (gemm_response),
      .response_valid     (processor_response_valid),
      .response_ready     (processor_response_ready),
      .response           (processor_response),
      .busy               (processor_busy),
      .scheduler_stalled  (scheduler_stalled),
      .command_completed  (command_completed),
      .command_error      (command_error)
  );

  dma_command_adapter u_dma_command_adapter (
      .clk                       (clk),
      .rst_n                     (rst_n),
      .command_valid             (dma_command_valid),
      .command_ready             (dma_command_ready),
      .command                   (dma_command),
      .response_valid            (dma_response_valid),
      .response_ready            (dma_response_ready),
      .response                  (dma_response),
      .mmio_start                (mmio_dma_start),
      .mmio_source_address       (mmio_dma_source_address),
      .mmio_destination_address  (mmio_dma_destination_address),
      .mmio_length_bytes         (mmio_dma_length_bytes),
      .engine_start              (dma_engine_start),
      .engine_source_address     (dma_engine_source_address),
      .engine_destination_address(dma_engine_destination_address),
      .engine_length_bytes       (dma_engine_length_bytes),
      .engine_busy               (dma_busy),
      .engine_done               (dma_done),
      .engine_error              (dma_error),
      .engine_error_code         (dma_error_code)
  );

  dma_engine u_dma_engine (
      .clk                (clk),
      .rst_n              (rst_n),
      .start              (dma_engine_start),
      .source_address     (dma_engine_source_address),
      .destination_address(dma_engine_destination_address),
      .length_bytes       (dma_engine_length_bytes),
      .start_accepted     (dma_start_accepted),
      .start_rejected     (dma_start_rejected),
      .busy               (dma_busy),
      .done               (dma_done),
      .error              (dma_error),
      .error_code         (dma_error_code),
      .source_port        (dma_source_bus),
      .destination_port   (dma_destination_bus),
      .active_cycle       (dma_active_cycle),
      .stalled_cycle      (dma_stalled_cycle),
      .bytes_read_event   (dma_bytes_read),
      .bytes_written_event(dma_bytes_written)
  );

  vector_accelerator u_vector_accelerator (
      .clk                     (clk),
      .rst_n                   (rst_n),
      .command_valid           (vector_command_valid),
      .command_ready           (vector_command_ready),
      .command                 (vector_command),
      .response_valid          (vector_response_valid),
      .response_ready          (vector_response_ready),
      .response                (vector_response),
      .memory_port             (vector_memory_bus),
      .busy                    (vector_busy),
      .done                    (vector_done),
      .error                   (vector_error),
      .error_code              (vector_error_code),
      .active_cycle            (vector_active_cycle),
      .stalled_cycle           (vector_stalled_cycle),
      .elements_completed_event(vector_elements_completed)
  );

  reduction_accelerator u_reduction_accelerator (
      .clk                     (clk),
      .rst_n                   (rst_n),
      .command_valid           (reduction_command_valid),
      .command_ready           (reduction_command_ready),
      .command                 (reduction_command),
      .response_valid          (reduction_response_valid),
      .response_ready          (reduction_response_ready),
      .response                (reduction_response),
      .memory_port             (reduction_memory_bus),
      .busy                    (reduction_busy),
      .done                    (reduction_done),
      .error                   (reduction_error),
      .error_code              (reduction_error_code),
      .active_cycle            (reduction_active_cycle),
      .stalled_cycle           (reduction_stalled_cycle),
      .elements_completed_event(reduction_elements_completed)
  );

  gemm_accelerator u_gemm_accelerator (
      .clk                    (clk),
      .rst_n                  (rst_n),
      .command_valid          (gemm_command_valid),
      .command_ready          (gemm_command_ready),
      .command                (gemm_command),
      .response_valid         (gemm_response_valid),
      .response_ready         (gemm_response_ready),
      .response               (gemm_response),
      .memory_port            (gemm_memory_bus),
      .busy                   (gemm_busy),
      .done                   (gemm_done),
      .error                  (gemm_error),
      .error_code             (gemm_error_code),
      .active_cycle           (gemm_active_cycle),
      .stalled_cycle          (gemm_stalled_cycle),
      .outputs_completed_event(gemm_outputs_completed)
  );

  soc_memory_fabric u_memory_fabric (
      .clk                 (clk),
      .rst_n               (rst_n),
      .dma_source_port     (dma_source_bus),
      .dma_destination_port(dma_destination_bus),
      .vector_port         (vector_memory_bus),
      .reduction_port      (reduction_memory_bus),
      .gemm_port           (gemm_memory_bus),
      .external_port       (external_memory_bus),
      .busy                (fabric_busy),
      .error_event         (fabric_error_event)
  );

  soc_timer u_timer (
      .clk     (clk),
      .rst_n   (rst_n),
      .enable  (timer_enable),
      .periodic(timer_periodic),
      .interval(timer_interval),
      .value   (timer_value),
      .tick    (timer_tick),
      .active  (timer_active)
  );

  irq_controller u_irq_controller (
      .clk                   (clk),
      .rst_n                 (rst_n),
      .sources               (irq_sources),
      .enable                (irq_enable),
      .clear                 (irq_clear),
      .pending               (irq_pending),
      .irq                   (irq),
      .service_latency_valid (irq_latency_valid),
      .service_latency_cycles(irq_latency_cycles)
  );

  performance_counters u_performance_counters (
      .clk               (clk),
      .rst_n             (rst_n),
      .clear             (perf_clear),
      .dma_active        (dma_active_cycle),
      .dma_stalled       (dma_stalled_cycle),
      .accel_active      (accelerator_active),
      .accel_stalled     (accelerator_stalled),
      .queue_occupancy   (queue_occupancy_register),
      .command_completed (command_completed),
      .bytes_read        (dma_bytes_read),
      .bytes_written     (dma_bytes_written),
      .irq_latency_valid (irq_latency_valid),
      .irq_latency_cycles(irq_latency_cycles),
      .scheduler_stalled (scheduler_stalled),
      .select            (perf_select),
      .selected_value    (perf_value)
  );

  property p_irq_matches_enabled_pending;
    @(posedge clk) disable iff (!rst_n) irq == (|(irq_pending & irq_enable));
  endproperty

  property p_queue_count_matches_empty;
    @(posedge clk) disable iff (!rst_n) queue_empty == (queue_occupancy == '0);
  endproperty

  property p_accelerator_commands_are_one_hot;
    @(posedge clk) disable iff (!rst_n) $onehot0(
        {vector_command_valid, reduction_command_valid, gemm_command_valid}
    );
  endproperty

  property p_known_top_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {
          soc_busy,
          irq,
          dma_busy,
          processor_busy,
          queue_full,
          queue_empty,
          fabric_busy,
          command_completed
        }
    );
  endproperty

  property p_internal_events_known;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {
          timer_active,
          dma_start_accepted,
          dma_start_rejected,
          queue_selected_starved,
          vector_elements_completed,
          reduction_elements_completed,
          gemm_outputs_completed
        }
    );
  endproperty

  a_irq_matches_enabled_pending :
  assert property (p_irq_matches_enabled_pending);
  a_queue_count_matches_empty :
  assert property (p_queue_count_matches_empty);
  a_accelerator_commands_are_one_hot :
  assert property (p_accelerator_commands_are_one_hot);
  a_known_top_control :
  assert property (p_known_top_control);
  a_internal_events_known :
  assert property (p_internal_events_known);

endmodule
