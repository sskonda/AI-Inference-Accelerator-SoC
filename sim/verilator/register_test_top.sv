module register_test_top (
  input  logic                                clk,
  input  logic                                rst_n,
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

  input  logic                                           soc_busy,
  output logic                                           global_enable,
  output logic                                           perf_clear,
  output logic                                           scheduler_priority_mode,
  output logic [accel_pkg::STARVATION_COUNTER_WIDTH-1:0] scheduler_starvation_threshold,

  input  logic [soc_pkg::IRQ_SOURCE_COUNT-1:0] irq_pending,
  output logic [soc_pkg::IRQ_SOURCE_COUNT-1:0] irq_enable,
  output logic [soc_pkg::IRQ_SOURCE_COUNT-1:0] irq_clear,

  input  logic [          soc_pkg::DATA_WIDTH-1:0] timer_value,
  output logic                                     timer_enable,
  output logic                                     timer_periodic,
  output logic [reg_pkg::TIMER_INTERVAL_WIDTH-1:0] timer_interval,

  input  logic                                 dma_busy,
  input  logic                                 dma_done,
  input  logic                                 dma_error,
  output logic                                 dma_start,
  output logic                                 dma_irq_enable,
  output logic [      soc_pkg::ADDR_WIDTH-1:0] dma_src_addr,
  output logic [      soc_pkg::ADDR_WIDTH-1:0] dma_dst_addr,
  output logic [soc_pkg::BYTE_COUNT_WIDTH-1:0] dma_length_bytes,

  input logic                                       queue_full,
  input logic                                       queue_empty,
  input logic [ reg_pkg::QUEUE_OCCUPANCY_WIDTH-1:0] queue_occupancy,
  input logic [reg_pkg::QUEUE_HIGH_WATER_WIDTH-1:0] queue_high_water,

  output logic [soc_pkg::PERF_COUNTER_ID_WIDTH-1:0] perf_select,
  input  logic [   soc_pkg::PERF_COUNTER_WIDTH-1:0] perf_value,

  input  logic                                   cmd_ready,
  input  logic                                   cmd_full,
  output logic                                   cmd_valid,
  output logic [    accel_pkg::OPCODE_WIDTH-1:0] cmd_opcode,
  output logic [        soc_pkg::ADDR_WIDTH-1:0] cmd_src0_addr,
  output logic [        soc_pkg::ADDR_WIDTH-1:0] cmd_src1_addr,
  output logic [        soc_pkg::ADDR_WIDTH-1:0] cmd_dst_addr,
  output logic [    accel_pkg::LENGTH_WIDTH-1:0] cmd_length,
  output logic [ accel_pkg::DIMENSION_WIDTH-1:0] cmd_m,
  output logic [ accel_pkg::DIMENSION_WIDTH-1:0] cmd_n,
  output logic [ accel_pkg::DIMENSION_WIDTH-1:0] cmd_k,
  output logic [     accel_pkg::FLAGS_WIDTH-1:0] cmd_flags,
  output logic [  accel_pkg::PRIORITY_WIDTH-1:0] cmd_priority,
  output logic [accel_pkg::COMMAND_ID_WIDTH-1:0] cmd_id,

  input  logic                                   rsp_valid,
  output logic                                   rsp_ready,
  input  logic                                   rsp_empty,
  input  logic [accel_pkg::COMMAND_ID_WIDTH-1:0] rsp_command_id,
  input  logic [    accel_pkg::OPCODE_WIDTH-1:0] rsp_opcode,
  input  logic [       soc_pkg::ERROR_WIDTH-1:0] rsp_error,
  input  logic [        soc_pkg::DATA_WIDTH-1:0] rsp_result,
  input  logic [        soc_pkg::DATA_WIDTH-1:0] rsp_cycles,

  input  logic [soc_pkg::ERROR_STATUS_WIDTH-1:0] hardware_error_set,
  output logic [soc_pkg::ERROR_STATUS_WIDTH-1:0] error_status,
  output logic [        soc_pkg::DATA_WIDTH-1:0] definition_checksum
);

  axil_if axil_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  cmd_if command_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  protocol_compile_top u_protocol_compile (
      .clk                (clk),
      .rst_n              (rst_n),
      .definition_checksum(definition_checksum)
  );

  always_comb begin
    axil_bus.awvalid = axil_awvalid;
    axil_bus.awaddr = axil_awaddr;
    axil_awready = axil_bus.awready;
    axil_bus.wvalid = axil_wvalid;
    axil_bus.wdata = axil_wdata;
    axil_bus.wstrb = axil_wstrb;
    axil_wready = axil_bus.wready;
    axil_bvalid = axil_bus.bvalid;
    axil_bus.bready = axil_bready;
    axil_bresp = axil_bus.bresp;
    axil_bus.arvalid = axil_arvalid;
    axil_bus.araddr = axil_araddr;
    axil_arready = axil_bus.arready;
    axil_rvalid = axil_bus.rvalid;
    axil_bus.rready = axil_rready;
    axil_rdata = axil_bus.rdata;
    axil_rresp = axil_bus.rresp;

    command_bus.cmd_ready = cmd_ready;
    command_bus.cmd_full = cmd_full;
    cmd_valid = command_bus.cmd_valid;
    cmd_opcode = command_bus.cmd.opcode;
    cmd_src0_addr = command_bus.cmd.src0_addr;
    cmd_src1_addr = command_bus.cmd.src1_addr;
    cmd_dst_addr = command_bus.cmd.dst_addr;
    cmd_length = command_bus.cmd.length;
    cmd_m = command_bus.cmd.m;
    cmd_n = command_bus.cmd.n;
    cmd_k = command_bus.cmd.k;
    cmd_flags = command_bus.cmd.flags;
    cmd_priority = command_bus.cmd.priority_level;
    cmd_id = command_bus.cmd.command_id;

    command_bus.rsp_valid = rsp_valid;
    rsp_ready = command_bus.rsp_ready;
    command_bus.rsp_empty = rsp_empty;
    command_bus.rsp.command_id = rsp_command_id;
    command_bus.rsp.opcode = accel_pkg::command_opcode_e'(rsp_opcode);
    command_bus.rsp.error = soc_pkg::error_e'(rsp_error);
    command_bus.rsp.result = rsp_result;
    command_bus.rsp.cycles = rsp_cycles;
  end

  soc_register_block u_register_block (
      .clk                           (clk),
      .rst_n                         (rst_n),
      .axil                          (axil_bus),
      .command_port                  (command_bus),
      .soc_busy                      (soc_busy),
      .global_enable                 (global_enable),
      .perf_clear                    (perf_clear),
      .scheduler_priority_mode       (scheduler_priority_mode),
      .scheduler_starvation_threshold(scheduler_starvation_threshold),
      .irq_pending                   (irq_pending),
      .irq_enable                    (irq_enable),
      .irq_clear                     (irq_clear),
      .timer_value                   (timer_value),
      .timer_enable                  (timer_enable),
      .timer_periodic                (timer_periodic),
      .timer_interval                (timer_interval),
      .dma_busy                      (dma_busy),
      .dma_done                      (dma_done),
      .dma_error                     (dma_error),
      .dma_start                     (dma_start),
      .dma_irq_enable                (dma_irq_enable),
      .dma_src_addr                  (dma_src_addr),
      .dma_dst_addr                  (dma_dst_addr),
      .dma_length_bytes              (dma_length_bytes),
      .queue_full                    (queue_full),
      .queue_empty                   (queue_empty),
      .queue_occupancy               (queue_occupancy),
      .queue_high_water              (queue_high_water),
      .perf_select                   (perf_select),
      .perf_value                    (perf_value),
      .hardware_error_set            (hardware_error_set),
      .error_status                  (error_status)
  );

endmodule
