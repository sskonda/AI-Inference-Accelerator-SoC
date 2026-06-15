module protocol_compile_top (
  input  logic                           clk,
  input  logic                           rst_n,
  output logic [soc_pkg::DATA_WIDTH-1:0] definition_checksum
);

  axil_if axil_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  mem_if memory_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  stream_if stream_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  irq_if interrupt_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  cmd_if command_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  always_comb begin
    definition_checksum = reg_pkg::SOC_ID_VALUE ^ reg_pkg::VERSION_VALUE;
    definition_checksum = definition_checksum ^ reg_pkg::CTRL_ENABLE_BIT ^
        reg_pkg::CTRL_PERF_CLEAR_BIT ^ reg_pkg::CTRL_PRIORITY_POLICY_BIT;
    definition_checksum = definition_checksum ^ reg_pkg::STATUS_READY_BIT ^
        reg_pkg::STATUS_BUSY_BIT ^ reg_pkg::STATUS_ERROR_BIT;
    definition_checksum = definition_checksum ^ reg_pkg::TIMER_ENABLE_BIT ^
        reg_pkg::TIMER_PERIODIC_BIT ^ reg_pkg::TIMER_INTERVAL_LSB ^ reg_pkg::TIMER_INTERVAL_WIDTH;
    definition_checksum = definition_checksum ^ reg_pkg::DMA_CTRL_START_BIT ^
        reg_pkg::DMA_CTRL_IRQ_ENABLE_BIT ^ reg_pkg::DMA_STATUS_BUSY_BIT ^
        reg_pkg::DMA_STATUS_DONE_BIT ^ reg_pkg::DMA_STATUS_ERROR_BIT;
    definition_checksum = definition_checksum ^ reg_pkg::CMD_SUBMIT_BIT ^
        reg_pkg::CMD_STATUS_DONE_BIT ^ reg_pkg::CMD_STATUS_ERROR_BIT ^
        reg_pkg::CMD_STATUS_FULL_BIT ^ reg_pkg::CMD_STATUS_EMPTY_BIT;
    definition_checksum = definition_checksum ^ reg_pkg::SCHED_POLICY_BIT ^
        reg_pkg::SCHED_STARVATION_LSB ^ reg_pkg::SCHED_STARVATION_WIDTH;
    definition_checksum = definition_checksum ^ accel_pkg::ELEMENT_WIDTH ^ accel_pkg::ACCUM_WIDTH ^
        accel_pkg::FLAG_SIGNED_BIT ^ accel_pkg::FLAG_SATURATE_BIT ^ accel_pkg::FLAG_IRQ_ON_DONE_BIT;
    definition_checksum = definition_checksum ^ soc_pkg::IRQ_DMA_DONE_BIT ^
        soc_pkg::IRQ_CMD_DONE_BIT ^ soc_pkg::IRQ_ACCEL_DONE_BIT ^ soc_pkg::IRQ_ERROR_BIT ^
        soc_pkg::IRQ_TIMER_BIT;
    definition_checksum = definition_checksum ^ soc_pkg::DEFAULT_FIFO_DEPTH ^
        soc_pkg::DEFAULT_COMMAND_QUEUE_DEPTH ^ soc_pkg::DEFAULT_RAM_ADDR_WIDTH ^
        soc_pkg::DEFAULT_DMA_BURST_BEATS;
    definition_checksum = definition_checksum ^ accel_pkg::EXECUTOR_TARGET_WIDTH ^
        accel_pkg::STARVATION_COUNTER_WIDTH ^ accel_pkg::DEFAULT_STARVATION_THRESHOLD ^
        accel_pkg::DEFAULT_MAX_VECTOR_LENGTH;
    definition_checksum = definition_checksum ^ soc_pkg::PERF_COUNTER_WIDTH ^
        soc_pkg::ERROR_STATUS_WIDTH ^ soc_pkg::WORD_ADDRESS_LSB ^ reg_pkg::CMD_STATUS_PENDING_BIT ^
        reg_pkg::QUEUE_OCCUPANCY_LSB ^ reg_pkg::QUEUE_OCCUPANCY_WIDTH ^
        reg_pkg::QUEUE_HIGH_WATER_LSB ^ reg_pkg::QUEUE_HIGH_WATER_WIDTH ^ reg_pkg::QUEUE_FULL_BIT ^
        reg_pkg::QUEUE_EMPTY_BIT;

    axil_bus.awvalid = 1'b0;
    axil_bus.awaddr = '0;
    axil_bus.wvalid = 1'b0;
    axil_bus.wdata = '0;
    axil_bus.wstrb = '0;
    axil_bus.bready = 1'b0;
    axil_bus.arvalid = 1'b0;
    axil_bus.araddr = '0;
    axil_bus.rready = 1'b0;
    axil_bus.awready = 1'b0;
    axil_bus.wready = 1'b0;
    axil_bus.bvalid = 1'b0;
    axil_bus.bresp = '0;
    axil_bus.arready = 1'b0;
    axil_bus.rvalid = 1'b0;
    axil_bus.rdata = '0;
    axil_bus.rresp = '0;

    memory_bus.req_valid = 1'b0;
    memory_bus.req_ready = 1'b0;
    memory_bus.req_write = 1'b0;
    memory_bus.req_addr = '0;
    memory_bus.req_wdata = '0;
    memory_bus.req_wstrb = '0;
    memory_bus.req_last = 1'b1;
    memory_bus.rsp_valid = 1'b0;
    memory_bus.rsp_ready = 1'b0;
    memory_bus.rsp_rdata = '0;
    memory_bus.rsp_error = 1'b0;

    stream_bus.valid = 1'b0;
    stream_bus.ready = 1'b0;
    stream_bus.data = '0;
    stream_bus.last = 1'b0;
    stream_bus.user = '0;

    interrupt_bus.sources = '0;
    interrupt_bus.pending = '0;
    interrupt_bus.enable = '0;
    interrupt_bus.clear = '0;
    interrupt_bus.irq = 1'b0;

    command_bus.cmd_valid = 1'b0;
    command_bus.cmd_ready = 1'b0;
    command_bus.cmd = '0;
    command_bus.cmd_full = 1'b0;
    command_bus.rsp_valid = 1'b0;
    command_bus.rsp_ready = 1'b0;
    command_bus.rsp = '0;
    command_bus.rsp_empty = 1'b1;
  end

endmodule
