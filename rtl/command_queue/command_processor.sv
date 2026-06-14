module command_processor (
  input logic clk,
  input logic rst_n,
  input logic execution_enable,

  input  logic                     queue_valid,
  output logic                     queue_ready,
  input  accel_pkg::command_desc_t queue_command,

  output logic                         dma_cmd_valid,
  input  logic                         dma_cmd_ready,
  output accel_pkg::command_desc_t     dma_cmd,
  input  logic                         dma_rsp_valid,
  output logic                         dma_rsp_ready,
  input  accel_pkg::command_response_t dma_rsp,

  output logic                         vector_cmd_valid,
  input  logic                         vector_cmd_ready,
  output accel_pkg::command_desc_t     vector_cmd,
  input  logic                         vector_rsp_valid,
  output logic                         vector_rsp_ready,
  input  accel_pkg::command_response_t vector_rsp,

  output logic                         reduction_cmd_valid,
  input  logic                         reduction_cmd_ready,
  output accel_pkg::command_desc_t     reduction_cmd,
  input  logic                         reduction_rsp_valid,
  output logic                         reduction_rsp_ready,
  input  accel_pkg::command_response_t reduction_rsp,

  output logic                         gemm_cmd_valid,
  input  logic                         gemm_cmd_ready,
  output accel_pkg::command_desc_t     gemm_cmd,
  input  logic                         gemm_rsp_valid,
  output logic                         gemm_rsp_ready,
  input  accel_pkg::command_response_t gemm_rsp,

  output logic                         response_valid,
  input  logic                         response_ready,
  output accel_pkg::command_response_t response,

  output logic busy,
  output logic scheduler_stalled,
  output logic command_completed,
  output logic command_error
);

  import accel_pkg::*;
  import soc_pkg::*;

  typedef enum logic [1:0] {
    PROCESSOR_IDLE,
    PROCESSOR_WAIT,
    PROCESSOR_RESPONSE
  } processor_state_e;

  localparam logic [DATA_WIDTH-1:0] MAXIMUM_CYCLE_COUNT = {DATA_WIDTH{1'b1}};

  processor_state_e                         state;
  logic              [COMMAND_ID_WIDTH-1:0] active_command_id;
  command_opcode_e                          active_opcode;
  executor_target_e                         active_target;
  data_t                                    active_cycles;
  command_response_t                        response_reg;

  executor_target_e                         queued_target;
  logic                                     selected_backend_ready;
  logic                                     selected_response_valid;
  error_e                                   selected_response_error;
  data_t                                    selected_response_result;
  data_t                                    selected_response_cycles;
  logic                                     selected_response_tags_match;
  logic                                     dispatch_fire;
  logic                                     completion_fire;

  always_comb begin
    queued_target = executor_for_opcode(queue_command.opcode);

    dma_cmd_valid = 1'b0;
    vector_cmd_valid = 1'b0;
    reduction_cmd_valid = 1'b0;
    gemm_cmd_valid = 1'b0;
    dma_cmd = queue_command;
    vector_cmd = queue_command;
    reduction_cmd = queue_command;
    gemm_cmd = queue_command;
    dma_rsp_ready = 1'b0;
    vector_rsp_ready = 1'b0;
    reduction_rsp_ready = 1'b0;
    gemm_rsp_ready = 1'b0;

    selected_backend_ready = 1'b0;
    case (queued_target)
      EXEC_TARGET_DMA: selected_backend_ready = dma_cmd_ready;
      EXEC_TARGET_VECTOR: selected_backend_ready = vector_cmd_ready;
      EXEC_TARGET_REDUCTION: selected_backend_ready = reduction_cmd_ready;
      EXEC_TARGET_GEMM: selected_backend_ready = gemm_cmd_ready;
      default: selected_backend_ready = 1'b0;
    endcase

    queue_ready = 1'b0;
    if ((state == PROCESSOR_IDLE) && execution_enable) begin
      if (queued_target == EXEC_TARGET_INVALID) begin
        queue_ready = 1'b1;
      end else begin
        if (queue_valid) begin
          case (queued_target)
            EXEC_TARGET_DMA: dma_cmd_valid = 1'b1;
            EXEC_TARGET_VECTOR: vector_cmd_valid = 1'b1;
            EXEC_TARGET_REDUCTION: reduction_cmd_valid = 1'b1;
            EXEC_TARGET_GEMM: gemm_cmd_valid = 1'b1;
            default: begin
            end
          endcase
        end
        queue_ready = selected_backend_ready;
      end
    end

    selected_response_valid = 1'b0;
    selected_response_error = ERR_NONE;
    selected_response_result = '0;
    selected_response_cycles = '0;
    selected_response_tags_match = 1'b1;
    if (state == PROCESSOR_WAIT) begin
      case (active_target)
        EXEC_TARGET_DMA: begin
          dma_rsp_ready = 1'b1;
          selected_response_valid = dma_rsp_valid;
          selected_response_error = dma_rsp.error;
          selected_response_result = dma_rsp.result;
          selected_response_cycles = dma_rsp.cycles;
          selected_response_tags_match = (dma_rsp.command_id == active_command_id) &&
              (dma_rsp.opcode == active_opcode);
        end
        EXEC_TARGET_VECTOR: begin
          vector_rsp_ready = 1'b1;
          selected_response_valid = vector_rsp_valid;
          selected_response_error = vector_rsp.error;
          selected_response_result = vector_rsp.result;
          selected_response_cycles = vector_rsp.cycles;
          selected_response_tags_match = (vector_rsp.command_id == active_command_id) &&
              (vector_rsp.opcode == active_opcode);
        end
        EXEC_TARGET_REDUCTION: begin
          reduction_rsp_ready = 1'b1;
          selected_response_valid = reduction_rsp_valid;
          selected_response_error = reduction_rsp.error;
          selected_response_result = reduction_rsp.result;
          selected_response_cycles = reduction_rsp.cycles;
          selected_response_tags_match = (reduction_rsp.command_id == active_command_id) &&
              (reduction_rsp.opcode == active_opcode);
        end
        EXEC_TARGET_GEMM: begin
          gemm_rsp_ready = 1'b1;
          selected_response_valid = gemm_rsp_valid;
          selected_response_error = gemm_rsp.error;
          selected_response_result = gemm_rsp.result;
          selected_response_cycles = gemm_rsp.cycles;
          selected_response_tags_match = (gemm_rsp.command_id == active_command_id) &&
              (gemm_rsp.opcode == active_opcode);
        end
        default: begin
        end
      endcase
    end

    dispatch_fire = queue_valid && queue_ready;
    completion_fire = selected_response_valid;
    response_valid = state == PROCESSOR_RESPONSE;
    response = response_reg;
    busy = state != PROCESSOR_IDLE;
    scheduler_stalled = queue_valid &&
        ((state != PROCESSOR_IDLE) || !execution_enable ||
         ((queued_target != EXEC_TARGET_INVALID) && !selected_backend_ready));
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= PROCESSOR_IDLE;
      active_command_id <= '0;
      active_opcode <= CMD_OP_INVALID;
      active_target <= EXEC_TARGET_INVALID;
      active_cycles <= '0;
      response_reg <= '0;
      command_completed <= 1'b0;
      command_error <= 1'b0;
    end else begin
      command_completed <= 1'b0;
      command_error <= 1'b0;

      unique case (state)
        PROCESSOR_IDLE: begin
          active_cycles <= '0;
          if (dispatch_fire) begin
            if (queued_target == EXEC_TARGET_INVALID) begin
              response_reg.command_id <= queue_command.command_id;
              response_reg.opcode <= queue_command.opcode;
              response_reg.error <= ERR_OPCODE;
              response_reg.result <= '0;
              response_reg.cycles <= '0;
              state <= PROCESSOR_RESPONSE;
              command_completed <= 1'b1;
              command_error <= 1'b1;
            end else begin
              active_command_id <= queue_command.command_id;
              active_opcode <= queue_command.opcode;
              active_target <= queued_target;
              state <= PROCESSOR_WAIT;
            end
          end
        end

        PROCESSOR_WAIT: begin
          if (active_cycles != MAXIMUM_CYCLE_COUNT) begin
            active_cycles <= active_cycles + 1'b1;
          end
          if (completion_fire) begin
            response_reg.command_id <= active_command_id;
            response_reg.opcode <= active_opcode;
            response_reg.error <= selected_response_error;
            response_reg.result <= selected_response_result;
            if (selected_response_cycles != '0) begin
              response_reg.cycles <= selected_response_cycles;
            end else if (active_cycles == MAXIMUM_CYCLE_COUNT) begin
              response_reg.cycles <= MAXIMUM_CYCLE_COUNT;
            end else begin
              response_reg.cycles <= active_cycles + 1'b1;
            end
            state <= PROCESSOR_RESPONSE;
            command_completed <= 1'b1;
            command_error <= selected_response_error != ERR_NONE;
          end
        end

        PROCESSOR_RESPONSE: begin
          if (response_valid && response_ready) begin
            state <= PROCESSOR_IDLE;
          end
        end

        default: state <= PROCESSOR_IDLE;
      endcase
    end
  end

  property p_response_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) response_valid &&
        !response_ready |=> response_valid && $stable(
        response
    );
  endproperty

  property p_dispatch_is_one_hot;
    @(posedge clk) disable iff (!rst_n) $onehot0(
        {dma_cmd_valid, vector_cmd_valid, reduction_cmd_valid, gemm_cmd_valid}
    );
  endproperty

  property p_queue_accept_has_cause;
    @(posedge clk) disable iff (!rst_n) dispatch_fire |-> (queued_target == EXEC_TARGET_INVALID) ||
        (dma_cmd_valid && dma_cmd_ready) || (vector_cmd_valid && vector_cmd_ready) ||
        (reduction_cmd_valid && reduction_cmd_ready) || (gemm_cmd_valid && gemm_cmd_ready);
  endproperty

  property p_no_accept_while_busy;
    @(posedge clk) disable iff (!rst_n) busy |-> !queue_ready;
  endproperty

  property p_completion_has_active_command;
    @(posedge clk) disable iff (!rst_n) completion_fire |-> state == PROCESSOR_WAIT;
  endproperty

  property p_completion_tags_match;
    @(posedge clk) disable iff (!rst_n) completion_fire |-> selected_response_tags_match;
  endproperty

  property p_backend_responses_are_one_hot;
    @(posedge clk) disable iff (!rst_n) $onehot0(
        {dma_rsp_valid, vector_rsp_valid, reduction_rsp_valid, gemm_rsp_valid}
    );
  endproperty

  property p_state_is_legal;
    @(posedge clk) disable iff (!rst_n)
        state inside {PROCESSOR_IDLE, PROCESSOR_WAIT, PROCESSOR_RESPONSE};
  endproperty

  property p_known_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {
          state,
          queue_ready,
          response_valid,
          busy,
          scheduler_stalled,
          command_completed,
          command_error
        }
    );
  endproperty

  a_response_stable_while_stalled :
  assert property (p_response_stable_while_stalled);
  a_dispatch_is_one_hot :
  assert property (p_dispatch_is_one_hot);
  a_queue_accept_has_cause :
  assert property (p_queue_accept_has_cause);
  a_no_accept_while_busy :
  assert property (p_no_accept_while_busy);
  a_completion_has_active_command :
  assert property (p_completion_has_active_command);
  a_completion_tags_match :
  assert property (p_completion_tags_match);
  a_backend_responses_are_one_hot :
  assert property (p_backend_responses_are_one_hot);
  a_state_is_legal :
  assert property (p_state_is_legal);
  a_known_control :
  assert property (p_known_control);

  c_dma_dispatch :
  cover property (
      @(posedge clk) disable iff (!rst_n) dispatch_fire && (queued_target == EXEC_TARGET_DMA));
  c_vector_dispatch :
  cover property (
      @(posedge clk) disable iff (!rst_n) dispatch_fire && (queued_target == EXEC_TARGET_VECTOR));
  c_reduction_dispatch :
  cover property (@(posedge clk) disable iff (!rst_n) dispatch_fire &&
                  (queued_target == EXEC_TARGET_REDUCTION));
  c_gemm_dispatch :
  cover property (
      @(posedge clk) disable iff (!rst_n) dispatch_fire && (queued_target == EXEC_TARGET_GEMM));
  c_invalid_opcode :
  cover property (
      @(posedge clk) disable iff (!rst_n) dispatch_fire && (queued_target == EXEC_TARGET_INVALID));
  c_executor_error :
  cover property (
      @(posedge clk) disable iff (!rst_n) completion_fire && (selected_response_error != ERR_NONE));

endmodule
