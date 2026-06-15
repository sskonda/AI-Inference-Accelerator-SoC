module soc_top_assertions (
  input logic                           clk,
  input logic                           rst_n,
  input logic                           memory_req_valid,
  input logic                           memory_req_ready,
  input logic                           memory_req_write,
  input logic [soc_pkg::ADDR_WIDTH-1:0] memory_req_addr,
  input logic [soc_pkg::DATA_WIDTH-1:0] memory_req_wdata,
  input logic [soc_pkg::STRB_WIDTH-1:0] memory_req_wstrb,
  input logic                           memory_req_last,
  input logic                           irq,
  input logic                           soc_busy,
  input logic                           debug_dma_done,
  input logic                           debug_command_completed,
  input logic                           debug_accelerator_done
);

  property p_memory_request_stable;
    @(posedge clk) disable iff (!rst_n) memory_req_valid &&
        !memory_req_ready |=> memory_req_valid && $stable(
        {memory_req_write, memory_req_addr, memory_req_wdata, memory_req_wstrb, memory_req_last}
    );
  endproperty

  property p_known_completion_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {irq, soc_busy, debug_dma_done, debug_command_completed, debug_accelerator_done}
    );
  endproperty

  property p_dma_done_after_busy;
    @(posedge clk) disable iff (!rst_n) debug_dma_done |-> $past(
        soc_busy
    );
  endproperty

  a_memory_request_stable :
  assert property (p_memory_request_stable);
  a_known_completion_control :
  assert property (p_known_completion_control);
  a_dma_done_after_busy :
  assert property (p_dma_done_after_busy);

endmodule

bind soc_top soc_top_assertions u_soc_top_assertions (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .memory_req_valid       (memory_req_valid),
    .memory_req_ready       (memory_req_ready),
    .memory_req_write       (memory_req_write),
    .memory_req_addr        (memory_req_addr),
    .memory_req_wdata       (memory_req_wdata),
    .memory_req_wstrb       (memory_req_wstrb),
    .memory_req_last        (memory_req_last),
    .irq                    (irq),
    .soc_busy               (soc_busy),
    .debug_dma_done         (debug_dma_done),
    .debug_command_completed(debug_command_completed),
    .debug_accelerator_done (debug_accelerator_done)
);
