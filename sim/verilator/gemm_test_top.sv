module gemm_test_top #(
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH,
    parameter int unsigned ELEMENT_WIDTH = accel_pkg::ELEMENT_WIDTH,
    parameter int unsigned ACCUM_WIDTH = accel_pkg::ACCUM_WIDTH,
    parameter int unsigned MAX_M = accel_pkg::DEFAULT_MAX_GEMM_M,
    parameter int unsigned MAX_N = accel_pkg::DEFAULT_MAX_GEMM_N,
    parameter int unsigned MAX_K = accel_pkg::DEFAULT_MAX_GEMM_K,
    parameter int unsigned TILE_M = accel_pkg::DEFAULT_GEMM_TILE_M,
    parameter int unsigned TILE_N = accel_pkg::DEFAULT_GEMM_TILE_N
) (
  input logic clk,
  input logic rst_n,

  input  logic                                   command_valid,
  output logic                                   command_ready,
  input  logic [    accel_pkg::OPCODE_WIDTH-1:0] command_opcode,
  input  logic [        soc_pkg::ADDR_WIDTH-1:0] command_src0_addr,
  input  logic [        soc_pkg::ADDR_WIDTH-1:0] command_src1_addr,
  input  logic [        soc_pkg::ADDR_WIDTH-1:0] command_dst_addr,
  input  logic [ accel_pkg::DIMENSION_WIDTH-1:0] command_m,
  input  logic [ accel_pkg::DIMENSION_WIDTH-1:0] command_n,
  input  logic [ accel_pkg::DIMENSION_WIDTH-1:0] command_k,
  input  logic [     accel_pkg::FLAGS_WIDTH-1:0] command_flags,
  input  logic [accel_pkg::COMMAND_ID_WIDTH-1:0] command_id,

  output logic                                   response_valid,
  input  logic                                   response_ready,
  output logic [accel_pkg::COMMAND_ID_WIDTH-1:0] response_command_id,
  output logic [    accel_pkg::OPCODE_WIDTH-1:0] response_opcode,
  output logic [       soc_pkg::ERROR_WIDTH-1:0] response_error,
  output logic [        soc_pkg::DATA_WIDTH-1:0] response_result,
  output logic [        soc_pkg::DATA_WIDTH-1:0] response_cycles,

  output logic                                           memory_req_valid,
  input  logic                                           memory_req_ready,
  output logic                                           memory_req_write,
  output logic [                soc_pkg::ADDR_WIDTH-1:0] memory_req_addr,
  output logic [                         DATA_WIDTH-1:0] memory_req_wdata,
  output logic [(DATA_WIDTH/soc_pkg::BITS_PER_BYTE)-1:0] memory_req_wstrb,
  output logic                                           memory_req_last,
  input  logic                                           memory_rsp_valid,
  output logic                                           memory_rsp_ready,
  input  logic [                         DATA_WIDTH-1:0] memory_rsp_rdata,
  input  logic                                           memory_rsp_error,

  output logic                               busy,
  output logic                               done,
  output logic                               error,
  output logic [   soc_pkg::ERROR_WIDTH-1:0] error_code,
  output logic                               active_cycle,
  output logic                               stalled_cycle,
  output logic [accel_pkg::LENGTH_WIDTH-1:0] outputs_completed_event,
  output logic [    soc_pkg::DATA_WIDTH-1:0] definition_checksum
);

  accel_pkg::command_desc_t     command;
  accel_pkg::command_response_t response_payload;

  mem_if #(
      .DATA_WIDTH(DATA_WIDTH)
  ) memory_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  protocol_compile_top u_protocol_compile (
      .clk                (clk),
      .rst_n              (rst_n),
      .definition_checksum(definition_checksum)
  );

  always_comb begin
    command.opcode = accel_pkg::command_opcode_e'(command_opcode);
    command.src0_addr = command_src0_addr;
    command.src1_addr = command_src1_addr;
    command.dst_addr = command_dst_addr;
    command.length = '0;
    command.m = command_m;
    command.n = command_n;
    command.k = command_k;
    command.flags = command_flags;
    command.priority_level = '0;
    command.command_id = command_id;

    response_command_id = response_payload.command_id;
    response_opcode = response_payload.opcode;
    response_error = response_payload.error;
    response_result = response_payload.result;
    response_cycles = response_payload.cycles;

    memory_req_valid = memory_bus.req_valid;
    memory_bus.req_ready = memory_req_ready;
    memory_req_write = memory_bus.req_write;
    memory_req_addr = memory_bus.req_addr;
    memory_req_wdata = memory_bus.req_wdata;
    memory_req_wstrb = memory_bus.req_wstrb;
    memory_req_last = memory_bus.req_last;
    memory_bus.rsp_valid = memory_rsp_valid;
    memory_rsp_ready = memory_bus.rsp_ready;
    memory_bus.rsp_rdata = memory_rsp_rdata;
    memory_bus.rsp_error = memory_rsp_error;
  end

  gemm_accelerator #(
      .DATA_WIDTH   (DATA_WIDTH),
      .ELEMENT_WIDTH(ELEMENT_WIDTH),
      .ACCUM_WIDTH  (ACCUM_WIDTH),
      .MAX_M        (MAX_M),
      .MAX_N        (MAX_N),
      .MAX_K        (MAX_K),
      .TILE_M       (TILE_M),
      .TILE_N       (TILE_N)
  ) u_gemm_accelerator (
      .clk                    (clk),
      .rst_n                  (rst_n),
      .command_valid          (command_valid),
      .command_ready          (command_ready),
      .command                (command),
      .response_valid         (response_valid),
      .response_ready         (response_ready),
      .response               (response_payload),
      .memory_port            (memory_bus),
      .busy                   (busy),
      .done                   (done),
      .error                  (error),
      .error_code             (error_code),
      .active_cycle           (active_cycle),
      .stalled_cycle          (stalled_cycle),
      .outputs_completed_event(outputs_completed_event)
  );

endmodule
