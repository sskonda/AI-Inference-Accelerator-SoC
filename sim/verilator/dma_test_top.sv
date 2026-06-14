module dma_test_top #(
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH,
    parameter int unsigned MAX_BURST_BEATS = soc_pkg::DEFAULT_DMA_BURST_BEATS
) (
  input logic clk,
  input logic rst_n,

  input  logic                                 start,
  input  logic [      soc_pkg::ADDR_WIDTH-1:0] source_address,
  input  logic [      soc_pkg::ADDR_WIDTH-1:0] destination_address,
  input  logic [soc_pkg::BYTE_COUNT_WIDTH-1:0] length_bytes,
  output logic                                 start_accepted,
  output logic                                 start_rejected,
  output logic                                 busy,
  output logic                                 done,
  output logic                                 error,
  output logic [     soc_pkg::ERROR_WIDTH-1:0] error_code,

  output logic                                           source_req_valid,
  input  logic                                           source_req_ready,
  output logic                                           source_req_write,
  output logic [                soc_pkg::ADDR_WIDTH-1:0] source_req_addr,
  output logic [                         DATA_WIDTH-1:0] source_req_wdata,
  output logic [(DATA_WIDTH/soc_pkg::BITS_PER_BYTE)-1:0] source_req_wstrb,
  output logic                                           source_req_last,
  input  logic                                           source_rsp_valid,
  output logic                                           source_rsp_ready,
  input  logic [                         DATA_WIDTH-1:0] source_rsp_rdata,
  input  logic                                           source_rsp_error,

  output logic                                           destination_req_valid,
  input  logic                                           destination_req_ready,
  output logic                                           destination_req_write,
  output logic [                soc_pkg::ADDR_WIDTH-1:0] destination_req_addr,
  output logic [                         DATA_WIDTH-1:0] destination_req_wdata,
  output logic [(DATA_WIDTH/soc_pkg::BITS_PER_BYTE)-1:0] destination_req_wstrb,
  output logic                                           destination_req_last,
  input  logic                                           destination_rsp_valid,
  output logic                                           destination_rsp_ready,
  input  logic [                         DATA_WIDTH-1:0] destination_rsp_rdata,
  input  logic                                           destination_rsp_error,

  output logic                                 active_cycle,
  output logic                                 stalled_cycle,
  output logic [soc_pkg::BYTE_COUNT_WIDTH-1:0] bytes_read_event,
  output logic [soc_pkg::BYTE_COUNT_WIDTH-1:0] bytes_written_event,
  output logic [      soc_pkg::DATA_WIDTH-1:0] definition_checksum
);

  mem_if #(
      .DATA_WIDTH(DATA_WIDTH)
  ) source_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  mem_if #(
      .DATA_WIDTH(DATA_WIDTH)
  ) destination_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  protocol_compile_top u_protocol_compile (
      .clk                (clk),
      .rst_n              (rst_n),
      .definition_checksum(definition_checksum)
  );

  always_comb begin
    source_req_valid = source_bus.req_valid;
    source_bus.req_ready = source_req_ready;
    source_req_write = source_bus.req_write;
    source_req_addr = source_bus.req_addr;
    source_req_wdata = source_bus.req_wdata;
    source_req_wstrb = source_bus.req_wstrb;
    source_req_last = source_bus.req_last;
    source_bus.rsp_valid = source_rsp_valid;
    source_rsp_ready = source_bus.rsp_ready;
    source_bus.rsp_rdata = source_rsp_rdata;
    source_bus.rsp_error = source_rsp_error;

    destination_req_valid = destination_bus.req_valid;
    destination_bus.req_ready = destination_req_ready;
    destination_req_write = destination_bus.req_write;
    destination_req_addr = destination_bus.req_addr;
    destination_req_wdata = destination_bus.req_wdata;
    destination_req_wstrb = destination_bus.req_wstrb;
    destination_req_last = destination_bus.req_last;
    destination_bus.rsp_valid = destination_rsp_valid;
    destination_rsp_ready = destination_bus.rsp_ready;
    destination_bus.rsp_rdata = destination_rsp_rdata;
    destination_bus.rsp_error = destination_rsp_error;
  end

  dma_engine #(
      .DATA_WIDTH     (DATA_WIDTH),
      .MAX_BURST_BEATS(MAX_BURST_BEATS)
  ) u_dma (
      .clk                (clk),
      .rst_n              (rst_n),
      .start              (start),
      .source_address     (source_address),
      .destination_address(destination_address),
      .length_bytes       (length_bytes),
      .start_accepted     (start_accepted),
      .start_rejected     (start_rejected),
      .busy               (busy),
      .done               (done),
      .error              (error),
      .error_code         (error_code),
      .source_port        (source_bus),
      .destination_port   (destination_bus),
      .active_cycle       (active_cycle),
      .stalled_cycle      (stalled_cycle),
      .bytes_read_event   (bytes_read_event),
      .bytes_written_event(bytes_written_event)
  );

endmodule
