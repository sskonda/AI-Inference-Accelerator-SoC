module command_test_top #(
    parameter int unsigned QUEUE_DEPTH = soc_pkg::DEFAULT_COMMAND_QUEUE_DEPTH,
    parameter int unsigned AGE_WIDTH   = accel_pkg::STARVATION_COUNTER_WIDTH,
    parameter int unsigned COUNT_WIDTH = soc_pkg::width_for_count(QUEUE_DEPTH)
) (
  input logic clk,
  input logic rst_n,
  input logic execution_enable,

  input  logic                                   push_valid,
  output logic                                   push_ready,
  input  logic [    accel_pkg::OPCODE_WIDTH-1:0] push_opcode,
  input  logic [        soc_pkg::ADDR_WIDTH-1:0] push_src0_addr,
  input  logic [        soc_pkg::ADDR_WIDTH-1:0] push_src1_addr,
  input  logic [        soc_pkg::ADDR_WIDTH-1:0] push_dst_addr,
  input  logic [    accel_pkg::LENGTH_WIDTH-1:0] push_length,
  input  logic [ accel_pkg::DIMENSION_WIDTH-1:0] push_m,
  input  logic [ accel_pkg::DIMENSION_WIDTH-1:0] push_n,
  input  logic [ accel_pkg::DIMENSION_WIDTH-1:0] push_k,
  input  logic [     accel_pkg::FLAGS_WIDTH-1:0] push_flags,
  input  logic [  accel_pkg::PRIORITY_WIDTH-1:0] push_priority,
  input  logic [accel_pkg::COMMAND_ID_WIDTH-1:0] push_command_id,

  input logic [accel_pkg::SCHEDULER_POLICY_WIDTH-1:0] policy,
  input logic [                        AGE_WIDTH-1:0] starvation_threshold,

  input  logic                                   dma_cmd_ready,
  input  logic                                   vector_cmd_ready,
  input  logic                                   reduction_cmd_ready,
  input  logic                                   gemm_cmd_ready,
  output logic                                   dma_cmd_valid,
  output logic                                   vector_cmd_valid,
  output logic                                   reduction_cmd_valid,
  output logic                                   gemm_cmd_valid,
  output logic [    accel_pkg::OPCODE_WIDTH-1:0] dispatch_opcode,
  output logic [accel_pkg::COMMAND_ID_WIDTH-1:0] dispatch_command_id,
  output logic [  accel_pkg::PRIORITY_WIDTH-1:0] dispatch_priority,
  output logic [        soc_pkg::DATA_WIDTH-1:0] dma_command_checksum,
  output logic [        soc_pkg::DATA_WIDTH-1:0] vector_command_checksum,
  output logic [        soc_pkg::DATA_WIDTH-1:0] reduction_command_checksum,
  output logic [        soc_pkg::DATA_WIDTH-1:0] gemm_command_checksum,

  input  logic                                        completion_valid,
  input  logic [accel_pkg::EXECUTOR_TARGET_WIDTH-1:0] completion_target,
  input  logic [     accel_pkg::COMMAND_ID_WIDTH-1:0] completion_command_id,
  input  logic [         accel_pkg::OPCODE_WIDTH-1:0] completion_opcode,
  input  logic [            soc_pkg::ERROR_WIDTH-1:0] completion_error,
  input  logic [             soc_pkg::DATA_WIDTH-1:0] completion_result,
  output logic                                        completion_ready,

  output logic                                   response_valid,
  input  logic                                   response_ready,
  output logic [accel_pkg::COMMAND_ID_WIDTH-1:0] response_command_id,
  output logic [    accel_pkg::OPCODE_WIDTH-1:0] response_opcode,
  output logic [       soc_pkg::ERROR_WIDTH-1:0] response_error,
  output logic [        soc_pkg::DATA_WIDTH-1:0] response_result,
  output logic [        soc_pkg::DATA_WIDTH-1:0] response_cycles,

  output logic                           queue_full,
  output logic                           queue_empty,
  output logic [        COUNT_WIDTH-1:0] queue_occupancy,
  output logic [        COUNT_WIDTH-1:0] queue_high_water,
  output logic                           selected_starved,
  output logic                           processor_busy,
  output logic                           scheduler_stalled,
  output logic                           command_completed,
  output logic                           command_error,
  output logic [soc_pkg::DATA_WIDTH-1:0] definition_checksum
);

  accel_pkg::command_desc_t     push_command;
  logic                         queue_pop_valid;
  logic                         queue_pop_ready;
  accel_pkg::command_desc_t     queue_pop_command;

  accel_pkg::command_desc_t     dma_command;
  accel_pkg::command_desc_t     vector_command;
  accel_pkg::command_desc_t     reduction_command;
  accel_pkg::command_desc_t     gemm_command;

  logic                         dma_rsp_valid;
  logic                         dma_rsp_ready;
  accel_pkg::command_response_t dma_response;
  logic                         vector_rsp_valid;
  logic                         vector_rsp_ready;
  accel_pkg::command_response_t vector_response;
  logic                         reduction_rsp_valid;
  logic                         reduction_rsp_ready;
  accel_pkg::command_response_t reduction_response;
  logic                         gemm_rsp_valid;
  logic                         gemm_rsp_ready;
  accel_pkg::command_response_t gemm_response;
  accel_pkg::command_response_t processor_response;

  function automatic soc_pkg::data_t command_checksum(input accel_pkg::command_desc_t command);
    soc_pkg::data_t value;

    value = soc_pkg::data_t'(command.opcode);
    value ^= command.src0_addr;
    value ^= command.src1_addr;
    value ^= command.dst_addr;
    value ^= soc_pkg::data_t'(command.length);
    value ^= soc_pkg::data_t'(command.m);
    value ^= soc_pkg::data_t'(command.n);
    value ^= soc_pkg::data_t'(command.k);
    value ^= soc_pkg::data_t'(command.flags);
    value ^= soc_pkg::data_t'(command.priority_level);
    value ^= soc_pkg::data_t'(command.command_id);
    return value;
  endfunction

  protocol_compile_top u_protocol_compile (
      .clk                (clk),
      .rst_n              (rst_n),
      .definition_checksum(definition_checksum)
  );

  always_comb begin
    push_command.opcode = accel_pkg::command_opcode_e'(push_opcode);
    push_command.src0_addr = push_src0_addr;
    push_command.src1_addr = push_src1_addr;
    push_command.dst_addr = push_dst_addr;
    push_command.length = push_length;
    push_command.m = push_m;
    push_command.n = push_n;
    push_command.k = push_k;
    push_command.flags = push_flags;
    push_command.priority_level = push_priority;
    push_command.command_id = push_command_id;

    dispatch_opcode = dma_command.opcode;
    dispatch_command_id = dma_command.command_id;
    dispatch_priority = dma_command.priority_level;
    dma_command_checksum = command_checksum(dma_command);
    vector_command_checksum = command_checksum(vector_command);
    reduction_command_checksum = command_checksum(reduction_command);
    gemm_command_checksum = command_checksum(gemm_command);

    dma_rsp_valid = completion_valid && (completion_target == accel_pkg::EXEC_TARGET_DMA);
    vector_rsp_valid = completion_valid && (completion_target == accel_pkg::EXEC_TARGET_VECTOR);
    reduction_rsp_valid = completion_valid &&
        (completion_target == accel_pkg::EXEC_TARGET_REDUCTION);
    gemm_rsp_valid = completion_valid && (completion_target == accel_pkg::EXEC_TARGET_GEMM);

    dma_response.command_id = completion_command_id;
    dma_response.opcode = accel_pkg::command_opcode_e'(completion_opcode);
    dma_response.error = soc_pkg::error_e'(completion_error);
    dma_response.result = completion_result;
    dma_response.cycles = '0;
    vector_response = dma_response;
    reduction_response = dma_response;
    gemm_response = dma_response;

    completion_ready = 1'b0;
    case (accel_pkg::executor_target_e'(completion_target))
      accel_pkg::EXEC_TARGET_DMA: completion_ready = dma_rsp_ready;
      accel_pkg::EXEC_TARGET_VECTOR: completion_ready = vector_rsp_ready;
      accel_pkg::EXEC_TARGET_REDUCTION: completion_ready = reduction_rsp_ready;
      accel_pkg::EXEC_TARGET_GEMM: completion_ready = gemm_rsp_ready;
      default: completion_ready = 1'b0;
    endcase

    response_command_id = processor_response.command_id;
    response_opcode = processor_response.opcode;
    response_error = processor_response.error;
    response_result = processor_response.result;
    response_cycles = processor_response.cycles;
  end

  command_queue #(
      .DEPTH    (QUEUE_DEPTH),
      .AGE_WIDTH(AGE_WIDTH)
  ) u_command_queue (
      .clk                 (clk),
      .rst_n               (rst_n),
      .push_valid          (push_valid),
      .push_ready          (push_ready),
      .push_command        (push_command),
      .select_enable       (execution_enable),
      .policy              (accel_pkg::scheduler_policy_e'(policy)),
      .starvation_threshold(starvation_threshold),
      .pop_valid           (queue_pop_valid),
      .pop_ready           (queue_pop_ready),
      .pop_command         (queue_pop_command),
      .selected_starved    (selected_starved),
      .full                (queue_full),
      .empty               (queue_empty),
      .occupancy           (queue_occupancy),
      .high_water          (queue_high_water)
  );

  command_processor u_command_processor (
      .clk                (clk),
      .rst_n              (rst_n),
      .execution_enable   (execution_enable),
      .queue_valid        (queue_pop_valid),
      .queue_ready        (queue_pop_ready),
      .queue_command      (queue_pop_command),
      .dma_cmd_valid      (dma_cmd_valid),
      .dma_cmd_ready      (dma_cmd_ready),
      .dma_cmd            (dma_command),
      .dma_rsp_valid      (dma_rsp_valid),
      .dma_rsp_ready      (dma_rsp_ready),
      .dma_rsp            (dma_response),
      .vector_cmd_valid   (vector_cmd_valid),
      .vector_cmd_ready   (vector_cmd_ready),
      .vector_cmd         (vector_command),
      .vector_rsp_valid   (vector_rsp_valid),
      .vector_rsp_ready   (vector_rsp_ready),
      .vector_rsp         (vector_response),
      .reduction_cmd_valid(reduction_cmd_valid),
      .reduction_cmd_ready(reduction_cmd_ready),
      .reduction_cmd      (reduction_command),
      .reduction_rsp_valid(reduction_rsp_valid),
      .reduction_rsp_ready(reduction_rsp_ready),
      .reduction_rsp      (reduction_response),
      .gemm_cmd_valid     (gemm_cmd_valid),
      .gemm_cmd_ready     (gemm_cmd_ready),
      .gemm_cmd           (gemm_command),
      .gemm_rsp_valid     (gemm_rsp_valid),
      .gemm_rsp_ready     (gemm_rsp_ready),
      .gemm_rsp           (gemm_response),
      .response_valid     (response_valid),
      .response_ready     (response_ready),
      .response           (processor_response),
      .busy               (processor_busy),
      .scheduler_stalled  (scheduler_stalled),
      .command_completed  (command_completed),
      .command_error      (command_error)
  );

endmodule
