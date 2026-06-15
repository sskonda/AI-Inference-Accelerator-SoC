module tb_top;
  import uvm_pkg::*;
  import soc_uvm_pkg::*;

  timeunit 1ns; timeprecision 1ps;

  localparam time CLOCK_HALF_PERIOD = 5ns;
  localparam int unsigned RESET_CYCLES = 5;

  logic                                                            clk = 1'b0;
  logic                                                            irq;
  logic                                                            soc_busy;
  logic                                                            debug_dma_done;
  logic                                                            debug_command_completed;
  logic                       [   accel_pkg::COMMAND_ID_WIDTH-1:0] debug_completed_command_id;
  accel_pkg::command_opcode_e                                      debug_completed_opcode;
  logic                                                            debug_command_error;
  logic                                                            debug_accelerator_done;
  logic                                                            debug_fabric_busy;
  logic                       [reg_pkg::QUEUE_OCCUPANCY_WIDTH-1:0] debug_queue_occupancy;
  logic                       [   soc_pkg::ERROR_STATUS_WIDTH-1:0] debug_error_status;
  logic                       [           soc_pkg::DATA_WIDTH-1:0] debug_definition_checksum;

  soc_reset_if reset_bus (.clk(clk));
  axil_if control_bus (
      .clk  (clk),
      .rst_n(reset_bus.rst_n)
  );
  mem_if memory_bus (
      .clk  (clk),
      .rst_n(reset_bus.rst_n)
  );
  soc_irq_if interrupt_bus (
      .clk  (clk),
      .rst_n(reset_bus.rst_n)
  );
  soc_command_monitor_if command_monitor_bus (
      .clk  (clk),
      .rst_n(reset_bus.rst_n)
  );

  always #(CLOCK_HALF_PERIOD) clk = ~clk;

  assign interrupt_bus.irq = irq;
  assign command_monitor_bus.command_completed = debug_command_completed;
  assign command_monitor_bus.command_id = debug_completed_command_id;
  assign command_monitor_bus.opcode = debug_completed_opcode;
  assign command_monitor_bus.error = debug_command_error;
  assign command_monitor_bus.queue_occupancy = debug_queue_occupancy;

  soc_top dut (
      .clk                       (clk),
      .rst_n                     (reset_bus.rst_n),
      .axil_awvalid              (control_bus.awvalid),
      .axil_awready              (control_bus.awready),
      .axil_awaddr               (control_bus.awaddr),
      .axil_wvalid               (control_bus.wvalid),
      .axil_wready               (control_bus.wready),
      .axil_wdata                (control_bus.wdata),
      .axil_wstrb                (control_bus.wstrb),
      .axil_bvalid               (control_bus.bvalid),
      .axil_bready               (control_bus.bready),
      .axil_bresp                (control_bus.bresp),
      .axil_arvalid              (control_bus.arvalid),
      .axil_arready              (control_bus.arready),
      .axil_araddr               (control_bus.araddr),
      .axil_rvalid               (control_bus.rvalid),
      .axil_rready               (control_bus.rready),
      .axil_rdata                (control_bus.rdata),
      .axil_rresp                (control_bus.rresp),
      .memory_req_valid          (memory_bus.req_valid),
      .memory_req_ready          (memory_bus.req_ready),
      .memory_req_write          (memory_bus.req_write),
      .memory_req_addr           (memory_bus.req_addr),
      .memory_req_wdata          (memory_bus.req_wdata),
      .memory_req_wstrb          (memory_bus.req_wstrb),
      .memory_req_last           (memory_bus.req_last),
      .memory_rsp_valid          (memory_bus.rsp_valid),
      .memory_rsp_ready          (memory_bus.rsp_ready),
      .memory_rsp_rdata          (memory_bus.rsp_rdata),
      .memory_rsp_error          (memory_bus.rsp_error),
      .irq                       (irq),
      .soc_busy                  (soc_busy),
      .debug_dma_done            (debug_dma_done),
      .debug_command_completed   (debug_command_completed),
      .debug_completed_command_id(debug_completed_command_id),
      .debug_completed_opcode    (debug_completed_opcode),
      .debug_command_error       (debug_command_error),
      .debug_accelerator_done    (debug_accelerator_done),
      .debug_fabric_busy         (debug_fabric_busy),
      .debug_queue_occupancy     (debug_queue_occupancy),
      .debug_error_status        (debug_error_status),
      .debug_definition_checksum (debug_definition_checksum)
  );

  initial begin
    uvm_config_db#(virtual axil_if)::set(null, "uvm_test_top", "axil_vif", control_bus);
    uvm_config_db#(virtual mem_if)::set(null, "uvm_test_top", "memory_vif", memory_bus);
    uvm_config_db#(virtual soc_irq_if)::set(null, "uvm_test_top", "irq_vif", interrupt_bus);
    uvm_config_db#(virtual soc_command_monitor_if)::set(null, "uvm_test_top", "command_vif",
                                                        command_monitor_bus);
    uvm_config_db#(virtual soc_reset_if)::set(null, "uvm_test_top", "reset_vif", reset_bus);
    fork
      reset_bus.apply_reset(RESET_CYCLES);
    join_none
    run_test();
  end

endmodule
