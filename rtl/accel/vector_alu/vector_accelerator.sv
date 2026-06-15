module vector_accelerator #(
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH,
    parameter int unsigned ELEMENT_WIDTH = accel_pkg::ELEMENT_WIDTH,
    parameter int unsigned MAX_VECTOR_LENGTH = accel_pkg::DEFAULT_MAX_VECTOR_LENGTH
) (
  input logic clk,
  input logic rst_n,

  input  logic                         command_valid,
  output logic                         command_ready,
  input  accel_pkg::command_desc_t     command,
  output logic                         response_valid,
  input  logic                         response_ready,
  output accel_pkg::command_response_t response,

  mem_if.initiator memory_port,

  output logic                                          busy,
  output logic                                          done,
  output logic                                          error,
  output soc_pkg::error_e                               error_code,
  output logic                                          active_cycle,
  output logic                                          stalled_cycle,
  output logic            [accel_pkg::LENGTH_WIDTH-1:0] elements_completed_event
);

  import accel_pkg::*;
  import soc_pkg::*;

  localparam int unsigned VECTOR_DATA_BYTES = DATA_WIDTH / BITS_PER_BYTE;
  localparam int unsigned ELEMENT_BYTES = ELEMENT_WIDTH / BITS_PER_BYTE;
  localparam int unsigned ELEMENTS_PER_WORD = DATA_WIDTH / ELEMENT_WIDTH;
  localparam int unsigned CALC_WIDTH = (2 * ELEMENT_WIDTH) + 1;
  localparam int unsigned ELEMENT_COUNT_WIDTH = width_for_count(ELEMENTS_PER_WORD);
  localparam logic [LENGTH_WIDTH-1:0] MAXIMUM_COMMAND_LENGTH = '1;
  localparam data_t MAXIMUM_CYCLE_COUNT = '1;

  typedef logic [ELEMENT_WIDTH-1:0] element_t;
  typedef logic [ELEMENT_COUNT_WIDTH-1:0] element_count_t;
  typedef logic [DATA_WIDTH-1:0] vector_word_t;
  typedef logic [VECTOR_DATA_BYTES-1:0] vector_strb_t;
  typedef logic signed [CALC_WIDTH-1:0] signed_calc_t;
  typedef logic [CALC_WIDTH-1:0] unsigned_calc_t;

  typedef enum logic [3:0] {
    VECTOR_IDLE,
    VECTOR_SCALAR_REQUEST,
    VECTOR_SCALAR_RESPONSE,
    VECTOR_SOURCE0_REQUEST,
    VECTOR_SOURCE0_RESPONSE,
    VECTOR_SOURCE1_REQUEST,
    VECTOR_SOURCE1_RESPONSE,
    VECTOR_EXECUTE,
    VECTOR_WRITE_REQUEST,
    VECTOR_WRITE_RESPONSE,
    VECTOR_RESPONSE
  } vector_state_e;

  vector_state_e                            state;
  command_response_t                        response_reg;
  command_opcode_e                          active_opcode;
  logic              [     FLAGS_WIDTH-1:0] active_flags;
  logic              [COMMAND_ID_WIDTH-1:0] active_command_id;
  logic              [    LENGTH_WIDTH-1:0] active_length;
  addr_t                                    source0_address;
  addr_t                                    source1_address;
  addr_t                                    destination_address;
  logic              [    LENGTH_WIDTH-1:0] elements_remaining;
  vector_word_t                             source0_word;
  vector_word_t                             source1_word;
  element_t                                 scalar_element;
  vector_word_t                             result_word;
  data_t                                    active_cycles;

  logic                                     command_fire;
  logic                                     memory_request_fire;
  logic                                     memory_response_fire;
  logic                                     request_wait_state;
  logic                                     response_wait_state;
  logic                                     final_word;
  logic                                     operation_uses_source1;
  logic                                     operation_uses_scalar;
  logic                                     signed_mode;
  logic                                     saturate_mode;
  element_count_t                           current_word_elements;
  vector_strb_t                             current_write_strobe;
  vector_word_t                             computed_word;
  error_e                                   command_validation_error;
  logic              [BYTE_COUNT_WIDTH-1:0] vector_storage_bytes;

  function automatic logic address_is_word_aligned(input addr_t address);
    return (address % VECTOR_DATA_BYTES) == '0;
  endfunction

  function automatic logic scratchpad_range_is_legal(input addr_t address,
                                                     input byte_count_t length_bytes);
    logic [ADDR_WIDTH:0] final_address;
    logic [ADDR_WIDTH:0] scratchpad_limit;

    final_address = {1'b0, address} + (ADDR_WIDTH + 1)'(length_bytes);
    scratchpad_limit = {1'b0, SPM_BASE_ADDR} + SPM_SIZE_BYTES;
    return (length_bytes != '0) && ({1'b0, address} >= {1'b0, SPM_BASE_ADDR}) &&
        (final_address <= scratchpad_limit);
  endfunction

  function automatic vector_strb_t strobe_for_elements(input element_count_t element_count);
    vector_strb_t strobe;

    strobe = '0;
    for (int unsigned byte_index = 0; byte_index < VECTOR_DATA_BYTES; byte_index++) begin
      if (byte_index < (int'(element_count) * ELEMENT_BYTES)) begin
        strobe[byte_index] = 1'b1;
      end
    end
    return strobe;
  endfunction

  function automatic data_t completed_cycle_count(input data_t cycle_count);
    return (cycle_count == MAXIMUM_CYCLE_COUNT) ? MAXIMUM_CYCLE_COUNT : cycle_count + 1'b1;
  endfunction

  function automatic element_t execute_element(input element_t lhs, input element_t rhs,
                                               input command_opcode_e opcode,
                                               input logic use_signed, input logic use_saturation);
    signed_calc_t   signed_lhs;
    signed_calc_t   signed_rhs;
    signed_calc_t   signed_value;
    signed_calc_t   signed_maximum;
    signed_calc_t   signed_minimum;
    unsigned_calc_t unsigned_lhs;
    unsigned_calc_t unsigned_rhs;
    unsigned_calc_t unsigned_value;
    unsigned_calc_t unsigned_maximum;
    element_t       result;

    signed_lhs = signed_calc_t'($signed(lhs));
    signed_rhs = signed_calc_t'($signed(rhs));
    signed_value = '0;
    signed_maximum = (signed_calc_t'(1) <<< (ELEMENT_WIDTH - 1)) - 1'b1;
    signed_minimum = -(signed_calc_t'(1) <<< (ELEMENT_WIDTH - 1));
    unsigned_lhs = unsigned_calc_t'(lhs);
    unsigned_rhs = unsigned_calc_t'(rhs);
    unsigned_value = '0;
    unsigned_maximum = unsigned_calc_t'({ELEMENT_WIDTH{1'b1}});
    result = '0;

    if (use_signed) begin
      case (opcode)
        CMD_OP_VECTOR_ADD: signed_value = signed_lhs + signed_rhs;
        CMD_OP_VECTOR_MULTIPLY, CMD_OP_VECTOR_SCALE: signed_value = signed_lhs * signed_rhs;
        CMD_OP_VECTOR_RELU: signed_value = (signed_lhs < 0) ? '0 : signed_lhs;
        CMD_OP_VECTOR_CLAMP: begin
          if ((signed_lhs < 0) || (signed_rhs < 0)) begin
            signed_value = '0;
          end else if (signed_lhs > signed_rhs) begin
            signed_value = signed_rhs;
          end else begin
            signed_value = signed_lhs;
          end
        end
        default: signed_value = '0;
      endcase

      if (use_saturation && ((opcode == CMD_OP_VECTOR_ADD) || (opcode == CMD_OP_VECTOR_MULTIPLY) ||
                             (opcode == CMD_OP_VECTOR_SCALE))) begin
        if (signed_value > signed_maximum) begin
          result = element_t'(signed_maximum);
        end else if (signed_value < signed_minimum) begin
          result = element_t'(signed_minimum);
        end else begin
          result = element_t'(signed_value);
        end
      end else begin
        result = element_t'(signed_value);
      end
    end else begin
      case (opcode)
        CMD_OP_VECTOR_ADD: unsigned_value = unsigned_lhs + unsigned_rhs;
        CMD_OP_VECTOR_MULTIPLY, CMD_OP_VECTOR_SCALE: unsigned_value = unsigned_lhs * unsigned_rhs;
        CMD_OP_VECTOR_RELU: unsigned_value = unsigned_lhs;
        CMD_OP_VECTOR_CLAMP:
        unsigned_value = (unsigned_lhs > unsigned_rhs) ? unsigned_rhs : unsigned_lhs;
        default: unsigned_value = '0;
      endcase

      if (use_saturation && ((opcode == CMD_OP_VECTOR_ADD) || (opcode == CMD_OP_VECTOR_MULTIPLY) ||
                             (opcode == CMD_OP_VECTOR_SCALE)) &&
          (unsigned_value > unsigned_maximum)) begin
        result = element_t'(unsigned_maximum);
      end else begin
        result = element_t'(unsigned_value);
      end
    end

    return result;
  endfunction

  initial begin : validate_parameters
    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % BITS_PER_BYTE) != 0)) begin
      $fatal(1, "Vector data width must contain a positive whole number of bytes");
    end
    if ((ELEMENT_WIDTH == 0) || ((ELEMENT_WIDTH % BITS_PER_BYTE) != 0) ||
        ((DATA_WIDTH % ELEMENT_WIDTH) != 0)) begin
      $fatal(1, "Vector element width must byte-align and divide the memory data width");
    end
    if ((MAX_VECTOR_LENGTH == 0) || (MAX_VECTOR_LENGTH > int'(MAXIMUM_COMMAND_LENGTH))) begin
      $fatal(1, "Vector maximum length must fit the command length field");
    end
    if (($bits(
            memory_port.req_wdata
        ) != DATA_WIDTH) || ($bits(
            memory_port.req_wstrb
        ) != VECTOR_DATA_BYTES)) begin
      $fatal(1, "Vector accelerator and memory-interface data widths must match");
    end
  end

  always_comb begin
    operation_uses_source1 = vector_opcode_uses_source1(active_opcode);
    operation_uses_scalar = active_opcode == CMD_OP_VECTOR_SCALE;
    signed_mode = active_flags[FLAG_SIGNED_BIT];
    saturate_mode = active_flags[FLAG_SATURATE_BIT];

    if (elements_remaining > LENGTH_WIDTH'(ELEMENTS_PER_WORD)) begin
      current_word_elements = element_count_t'(ELEMENTS_PER_WORD);
    end else begin
      current_word_elements = element_count_t'(elements_remaining);
    end
    final_word = elements_remaining <= LENGTH_WIDTH'(ELEMENTS_PER_WORD);
    current_write_strobe = strobe_for_elements(current_word_elements);

    computed_word = '0;
    for (int unsigned lane = 0; lane < ELEMENTS_PER_WORD; lane++) begin
      if (lane < int'(current_word_elements)) begin
        if (operation_uses_scalar) begin
          computed_word[lane*ELEMENT_WIDTH+:ELEMENT_WIDTH] = execute_element(
            source0_word[lane*ELEMENT_WIDTH+:ELEMENT_WIDTH],
            scalar_element,
            active_opcode,
            signed_mode,
            saturate_mode
          );
        end else begin
          computed_word[lane*ELEMENT_WIDTH+:ELEMENT_WIDTH] = execute_element(
            source0_word[lane*ELEMENT_WIDTH+:ELEMENT_WIDTH],
            source1_word[lane*ELEMENT_WIDTH+:ELEMENT_WIDTH],
            active_opcode,
            signed_mode,
            saturate_mode
          );
        end
      end
    end

    vector_storage_bytes = byte_count_t
        '(((int'(command.length) + ELEMENTS_PER_WORD - 1) / ELEMENTS_PER_WORD) * VECTOR_DATA_BYTES);
    command_validation_error = ERR_NONE;
    if (!is_vector_opcode(command.opcode)) begin
      command_validation_error = ERR_OPCODE;
    end else
        if ((command.length == '0) || (command.length > LENGTH_WIDTH'(MAX_VECTOR_LENGTH))) begin
      command_validation_error = ERR_DIMENSION;
    end else if (!address_is_word_aligned(
            command.src0_addr
        ) || !address_is_word_aligned(
            command.dst_addr
        ) || ((vector_opcode_uses_source1(
            command.opcode
        ) || (command.opcode == CMD_OP_VECTOR_SCALE)) && !address_is_word_aligned(
            command.src1_addr
        ))) begin
      command_validation_error = ERR_ADDRESS;
    end else if (!scratchpad_range_is_legal(
            command.src0_addr, vector_storage_bytes
        ) || !scratchpad_range_is_legal(
            command.dst_addr, vector_storage_bytes
        )) begin
      command_validation_error = ERR_SPM_BOUNDS;
    end else if (vector_opcode_uses_source1(
            command.opcode
        ) && !scratchpad_range_is_legal(
            command.src1_addr, vector_storage_bytes
        )) begin
      command_validation_error = ERR_SPM_BOUNDS;
    end else if ((command.opcode == CMD_OP_VECTOR_SCALE) && !scratchpad_range_is_legal(
            command.src1_addr, byte_count_t'(VECTOR_DATA_BYTES)
        )) begin
      command_validation_error = ERR_SPM_BOUNDS;
    end

    command_ready = rst_n && (state == VECTOR_IDLE);
    command_fire = command_valid && command_ready;

    memory_port.req_valid = rst_n &&
        ((state == VECTOR_SCALAR_REQUEST) || (state == VECTOR_SOURCE0_REQUEST) ||
         (state == VECTOR_SOURCE1_REQUEST) || (state == VECTOR_WRITE_REQUEST));
    memory_port.req_write = state == VECTOR_WRITE_REQUEST;
    memory_port.req_addr = source0_address;
    if (state == VECTOR_SCALAR_REQUEST) begin
      memory_port.req_addr = source1_address;
    end else if (state == VECTOR_SOURCE1_REQUEST) begin
      memory_port.req_addr = source1_address;
    end else if (state == VECTOR_WRITE_REQUEST) begin
      memory_port.req_addr = destination_address;
    end
    memory_port.req_wdata = result_word;
    memory_port.req_wstrb = (state == VECTOR_WRITE_REQUEST) ? current_write_strobe :
        vector_strb_t'('0);
    memory_port.req_last = (state == VECTOR_SCALAR_REQUEST) || final_word;
    memory_port.rsp_ready = rst_n &&
        ((state == VECTOR_SCALAR_RESPONSE) || (state == VECTOR_SOURCE0_RESPONSE) ||
         (state == VECTOR_SOURCE1_RESPONSE) || (state == VECTOR_WRITE_RESPONSE));
    memory_request_fire = memory_port.req_valid && memory_port.req_ready;
    memory_response_fire = memory_port.rsp_valid && memory_port.rsp_ready;
    request_wait_state = (state == VECTOR_SCALAR_REQUEST) || (state == VECTOR_SOURCE0_REQUEST) ||
        (state == VECTOR_SOURCE1_REQUEST) || (state == VECTOR_WRITE_REQUEST);
    response_wait_state = (state == VECTOR_SCALAR_RESPONSE) || (state == VECTOR_SOURCE0_RESPONSE) ||
        (state == VECTOR_SOURCE1_RESPONSE) || (state == VECTOR_WRITE_RESPONSE);

    response_valid = state == VECTOR_RESPONSE;
    response = response_reg;
    busy = state != VECTOR_IDLE;
    active_cycle = (state != VECTOR_IDLE) && (state != VECTOR_RESPONSE);
    stalled_cycle = busy && ((request_wait_state && !memory_port.req_ready) ||
                             (response_wait_state && !memory_port.rsp_valid) ||
                             ((state == VECTOR_RESPONSE) && !response_ready));
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= VECTOR_IDLE;
      response_reg <= '0;
      active_opcode <= CMD_OP_INVALID;
      active_flags <= '0;
      active_command_id <= '0;
      active_length <= '0;
      source0_address <= '0;
      source1_address <= '0;
      destination_address <= '0;
      elements_remaining <= '0;
      source0_word <= '0;
      source1_word <= '0;
      scalar_element <= '0;
      result_word <= '0;
      active_cycles <= '0;
      done <= 1'b0;
      error <= 1'b0;
      error_code <= ERR_NONE;
      elements_completed_event <= '0;
    end else begin
      done <= 1'b0;
      error <= 1'b0;
      error_code <= ERR_NONE;
      elements_completed_event <= '0;

      if (active_cycle && (active_cycles != MAXIMUM_CYCLE_COUNT)) begin
        active_cycles <= active_cycles + 1'b1;
      end

      unique case (state)
        VECTOR_IDLE: begin
          active_cycles <= '0;
          if (command_fire) begin
            active_opcode <= command.opcode;
            active_flags <= command.flags;
            active_command_id <= command.command_id;
            active_length <= command.length;
            if (command_validation_error != ERR_NONE) begin
              response_reg.command_id <= command.command_id;
              response_reg.opcode <= command.opcode;
              response_reg.error <= command_validation_error;
              response_reg.result <= '0;
              response_reg.cycles <= '0;
              done <= 1'b1;
              error <= 1'b1;
              error_code <= command_validation_error;
              state <= VECTOR_RESPONSE;
            end else begin
              source0_address <= command.src0_addr;
              source1_address <= command.src1_addr;
              destination_address <= command.dst_addr;
              elements_remaining <= command.length;
              if (command.opcode == CMD_OP_VECTOR_SCALE) begin
                state <= VECTOR_SCALAR_REQUEST;
              end else begin
                state <= VECTOR_SOURCE0_REQUEST;
              end
            end
          end
        end

        VECTOR_SCALAR_REQUEST: begin
          if (memory_request_fire) begin
            state <= VECTOR_SCALAR_RESPONSE;
          end
        end

        VECTOR_SCALAR_RESPONSE: begin
          if (memory_response_fire) begin
            if (memory_port.rsp_error) begin
              response_reg.command_id <= active_command_id;
              response_reg.opcode <= active_opcode;
              response_reg.error <= ERR_ADDRESS;
              response_reg.result <= '0;
              response_reg.cycles <= completed_cycle_count(active_cycles);
              done <= 1'b1;
              error <= 1'b1;
              error_code <= ERR_ADDRESS;
              state <= VECTOR_RESPONSE;
            end else begin
              scalar_element <= memory_port.rsp_rdata[0+:ELEMENT_WIDTH];
              state <= VECTOR_SOURCE0_REQUEST;
            end
          end
        end

        VECTOR_SOURCE0_REQUEST: begin
          if (memory_request_fire) begin
            state <= VECTOR_SOURCE0_RESPONSE;
          end
        end

        VECTOR_SOURCE0_RESPONSE: begin
          if (memory_response_fire) begin
            if (memory_port.rsp_error) begin
              response_reg.command_id <= active_command_id;
              response_reg.opcode <= active_opcode;
              response_reg.error <= ERR_ADDRESS;
              response_reg.result <= '0;
              response_reg.cycles <= completed_cycle_count(active_cycles);
              done <= 1'b1;
              error <= 1'b1;
              error_code <= ERR_ADDRESS;
              state <= VECTOR_RESPONSE;
            end else begin
              source0_word <= memory_port.rsp_rdata;
              if (operation_uses_source1) begin
                state <= VECTOR_SOURCE1_REQUEST;
              end else begin
                state <= VECTOR_EXECUTE;
              end
            end
          end
        end

        VECTOR_SOURCE1_REQUEST: begin
          if (memory_request_fire) begin
            state <= VECTOR_SOURCE1_RESPONSE;
          end
        end

        VECTOR_SOURCE1_RESPONSE: begin
          if (memory_response_fire) begin
            if (memory_port.rsp_error) begin
              response_reg.command_id <= active_command_id;
              response_reg.opcode <= active_opcode;
              response_reg.error <= ERR_ADDRESS;
              response_reg.result <= '0;
              response_reg.cycles <= completed_cycle_count(active_cycles);
              done <= 1'b1;
              error <= 1'b1;
              error_code <= ERR_ADDRESS;
              state <= VECTOR_RESPONSE;
            end else begin
              source1_word <= memory_port.rsp_rdata;
              state <= VECTOR_EXECUTE;
            end
          end
        end

        VECTOR_EXECUTE: begin
          result_word <= computed_word;
          state <= VECTOR_WRITE_REQUEST;
        end

        VECTOR_WRITE_REQUEST: begin
          if (memory_request_fire) begin
            state <= VECTOR_WRITE_RESPONSE;
          end
        end

        VECTOR_WRITE_RESPONSE: begin
          if (memory_response_fire) begin
            if (memory_port.rsp_error) begin
              response_reg.command_id <= active_command_id;
              response_reg.opcode <= active_opcode;
              response_reg.error <= ERR_ADDRESS;
              response_reg.result <= '0;
              response_reg.cycles <= completed_cycle_count(active_cycles);
              done <= 1'b1;
              error <= 1'b1;
              error_code <= ERR_ADDRESS;
              state <= VECTOR_RESPONSE;
            end else begin
              elements_completed_event <= LENGTH_WIDTH'(current_word_elements);
              if (final_word) begin
                response_reg.command_id <= active_command_id;
                response_reg.opcode <= active_opcode;
                response_reg.error <= ERR_NONE;
                response_reg.result <= DATA_WIDTH'(active_length);
                response_reg.cycles <= completed_cycle_count(active_cycles);
                done <= 1'b1;
                state <= VECTOR_RESPONSE;
              end else begin
                source0_address <= source0_address + VECTOR_DATA_BYTES;
                if (operation_uses_source1) begin
                  source1_address <= source1_address + VECTOR_DATA_BYTES;
                end
                destination_address <= destination_address + VECTOR_DATA_BYTES;
                elements_remaining <= elements_remaining - LENGTH_WIDTH'(ELEMENTS_PER_WORD);
                state <= VECTOR_SOURCE0_REQUEST;
              end
            end
          end
        end

        VECTOR_RESPONSE: begin
          if (response_valid && response_ready) begin
            state <= VECTOR_IDLE;
          end
        end

        default: begin
          response_reg.command_id <= active_command_id;
          response_reg.opcode <= active_opcode;
          response_reg.error <= ERR_INTERNAL;
          response_reg.result <= '0;
          response_reg.cycles <= active_cycles;
          done <= 1'b1;
          error <= 1'b1;
          error_code <= ERR_INTERNAL;
          state <= VECTOR_RESPONSE;
        end
      endcase
    end
  end

  property p_command_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) command_valid &&
        !command_ready |=> command_valid && $stable(
        command
    );
  endproperty

  property p_response_stable_while_stalled;
    @(posedge clk) disable iff (!rst_n) response_valid &&
        !response_ready |=> response_valid && $stable(
        response
    );
  endproperty

  property p_no_command_accept_while_busy;
    @(posedge clk) disable iff (!rst_n) busy |-> !command_ready;
  endproperty

  property p_memory_access_in_scratchpad;
    @(posedge clk) disable iff (!rst_n) memory_request_fire |-> scratchpad_range_is_legal(
        memory_port.req_addr, byte_count_t'(VECTOR_DATA_BYTES)
    );
  endproperty

  property p_write_has_expected_strobe;
    @(posedge clk) disable iff (!rst_n) memory_request_fire &&
        memory_port.req_write |-> memory_port.req_wstrb == current_write_strobe;
  endproperty

  property p_done_has_active_command;
    @(posedge clk) disable iff (!rst_n) done |-> $past(
        busy || command_fire
    );
  endproperty

  property p_error_implies_done;
    @(posedge clk) disable iff (!rst_n) error |-> done && (error_code != ERR_NONE);
  endproperty

  property p_state_is_legal;
    @(posedge clk) disable iff (!rst_n) state
        inside {VECTOR_IDLE, VECTOR_SCALAR_REQUEST, VECTOR_SCALAR_RESPONSE, VECTOR_SOURCE0_REQUEST,
                VECTOR_SOURCE0_RESPONSE, VECTOR_SOURCE1_REQUEST, VECTOR_SOURCE1_RESPONSE,
                VECTOR_EXECUTE, VECTOR_WRITE_REQUEST, VECTOR_WRITE_RESPONSE, VECTOR_RESPONSE};
  endproperty

  property p_known_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {
          state,
          command_ready,
          response_valid,
          busy,
          done,
          error,
          memory_port.req_valid,
          memory_port.rsp_ready
        }
    );
  endproperty

  a_command_stable_while_stalled :
  assert property (p_command_stable_while_stalled);
  a_response_stable_while_stalled :
  assert property (p_response_stable_while_stalled);
  a_no_command_accept_while_busy :
  assert property (p_no_command_accept_while_busy);
  a_memory_access_in_scratchpad :
  assert property (p_memory_access_in_scratchpad);
  a_write_has_expected_strobe :
  assert property (p_write_has_expected_strobe);
  a_done_has_active_command :
  assert property (p_done_has_active_command);
  a_error_implies_done :
  assert property (p_error_implies_done);
  a_state_is_legal :
  assert property (p_state_is_legal);
  a_known_control :
  assert property (p_known_control);

  c_vector_add :
  cover property (
      @(posedge clk) disable iff (!rst_n) command_fire && (command.opcode == CMD_OP_VECTOR_ADD));
  c_vector_multiply :
  cover property (@(posedge clk) disable iff (!rst_n) command_fire &&
                  (command.opcode == CMD_OP_VECTOR_MULTIPLY));
  c_vector_scale :
  cover property (
      @(posedge clk) disable iff (!rst_n) command_fire && (command.opcode == CMD_OP_VECTOR_SCALE));
  c_vector_relu :
  cover property (
      @(posedge clk) disable iff (!rst_n) command_fire && (command.opcode == CMD_OP_VECTOR_RELU));
  c_vector_clamp :
  cover property (
      @(posedge clk) disable iff (!rst_n) command_fire && (command.opcode == CMD_OP_VECTOR_CLAMP));
  c_partial_final_word :
  cover property (@(posedge clk) disable iff (!rst_n) memory_request_fire &&
                  memory_port.req_write && (current_write_strobe != '1));
  c_memory_stall :
  cover property (@(posedge clk) disable iff (!rst_n) stalled_cycle);
  c_saturating_operation :
  cover property (
      @(posedge clk) disable iff (!rst_n) command_fire && command.flags[FLAG_SATURATE_BIT]);

endmodule
