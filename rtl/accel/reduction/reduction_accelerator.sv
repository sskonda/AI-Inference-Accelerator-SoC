module reduction_accelerator #(
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH,
    parameter int unsigned ELEMENT_WIDTH = accel_pkg::ELEMENT_WIDTH,
    parameter int unsigned ACCUM_WIDTH = accel_pkg::ACCUM_WIDTH,
    parameter int unsigned MAX_REDUCTION_LENGTH = accel_pkg::DEFAULT_MAX_REDUCTION_LENGTH
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

  localparam int unsigned REDUCTION_DATA_BYTES = DATA_WIDTH / BITS_PER_BYTE;
  localparam int unsigned ELEMENT_BYTES = ELEMENT_WIDTH / BITS_PER_BYTE;
  localparam int unsigned ELEMENTS_PER_WORD = DATA_WIDTH / ELEMENT_WIDTH;
  localparam int unsigned TREE_LEVELS = $clog2(ELEMENTS_PER_WORD);
  localparam int unsigned ELEMENT_COUNT_WIDTH = width_for_count(ELEMENTS_PER_WORD);
  localparam int unsigned REQUIRED_SUM_WIDTH = ELEMENT_WIDTH + $clog2(MAX_REDUCTION_LENGTH);
  localparam logic [LENGTH_WIDTH-1:0] MAXIMUM_COMMAND_LENGTH = '1;
  localparam data_t MAXIMUM_CYCLE_COUNT = '1;

  typedef logic [ELEMENT_WIDTH-1:0] element_t;
  typedef logic [ELEMENT_COUNT_WIDTH-1:0] element_count_t;
  typedef logic [DATA_WIDTH-1:0] reduction_word_t;
  typedef logic [REDUCTION_DATA_BYTES-1:0] reduction_strb_t;
  typedef logic [ACCUM_WIDTH-1:0] accum_t;
  typedef logic signed [ACCUM_WIDTH-1:0] signed_accum_t;

  typedef enum logic [2:0] {
    REDUCTION_IDLE,
    REDUCTION_READ_REQUEST,
    REDUCTION_READ_RESPONSE,
    REDUCTION_ACCUMULATE,
    REDUCTION_WRITE_REQUEST,
    REDUCTION_WRITE_RESPONSE,
    REDUCTION_RESPONSE
  } reduction_state_e;

  reduction_state_e state;
  command_response_t response_reg;
  command_opcode_e active_opcode;
  logic [FLAGS_WIDTH-1:0] active_flags;
  logic [COMMAND_ID_WIDTH-1:0] active_command_id;
  logic [LENGTH_WIDTH-1:0] active_length;
  addr_t source_address;
  addr_t destination_address;
  logic [LENGTH_WIDTH-1:0] elements_remaining;
  reduction_word_t source_word;
  reduction_word_t result_word;
  accum_t accumulator;
  data_t active_cycles;

  accum_t sum_tree[TREE_LEVELS+1][ELEMENTS_PER_WORD];
  element_t max_tree[TREE_LEVELS+1][ELEMENTS_PER_WORD];
  accum_t word_sum;
  element_t word_maximum;
  accum_t next_accumulator;
  element_t reduced_element;
  reduction_word_t computed_result_word;
  reduction_strb_t result_write_strobe;

  logic command_fire;
  logic memory_request_fire;
  logic memory_response_fire;
  logic request_wait_state;
  logic response_wait_state;
  logic signed_mode;
  logic saturate_mode;
  logic final_word;
  element_count_t current_word_elements;
  error_e command_validation_error;
  byte_count_t source_storage_bytes;

  function automatic logic address_is_word_aligned(input addr_t address);
    return (address % REDUCTION_DATA_BYTES) == '0;
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

  function automatic data_t completed_cycle_count(input data_t cycle_count);
    return (cycle_count == MAXIMUM_CYCLE_COUNT) ? MAXIMUM_CYCLE_COUNT : cycle_count + 1'b1;
  endfunction

  function automatic element_t convert_sum(input accum_t value, input logic use_signed,
                                           input logic use_saturation);
    signed_accum_t signed_value;
    signed_accum_t signed_maximum;
    signed_accum_t signed_minimum;
    accum_t        unsigned_maximum;
    element_t      result;

    signed_value = signed_accum_t'(value);
    signed_maximum = (signed_accum_t'(1) <<< (ELEMENT_WIDTH - 1)) - 1'b1;
    signed_minimum = -(signed_accum_t'(1) <<< (ELEMENT_WIDTH - 1));
    unsigned_maximum = accum_t'({ELEMENT_WIDTH{1'b1}});
    result = element_t'(value);

    if (use_saturation) begin
      if (use_signed) begin
        if (signed_value > signed_maximum) begin
          result = element_t'(signed_maximum);
        end else if (signed_value < signed_minimum) begin
          result = element_t'(signed_minimum);
        end
      end else if (value > unsigned_maximum) begin
        result = element_t'(unsigned_maximum);
      end
    end
    return result;
  endfunction

  initial begin : validate_parameters
    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % BITS_PER_BYTE) != 0)) begin
      $fatal(1, "Reduction data width must contain a positive whole number of bytes");
    end
    if ((ELEMENT_WIDTH == 0) || ((ELEMENT_WIDTH % BITS_PER_BYTE) != 0) ||
        ((DATA_WIDTH % ELEMENT_WIDTH) != 0)) begin
      $fatal(1, "Reduction element width must byte-align and divide the memory data width");
    end
    if ((ELEMENTS_PER_WORD & (ELEMENTS_PER_WORD - 1)) != 0) begin
      $fatal(1, "Reduction lane count must be a power of two");
    end
    if ((MAX_REDUCTION_LENGTH == 0) || (MAX_REDUCTION_LENGTH > int'(MAXIMUM_COMMAND_LENGTH))) begin
      $fatal(1, "Reduction maximum length must fit the command length field");
    end
    if (ACCUM_WIDTH < REQUIRED_SUM_WIDTH) begin
      $fatal(1, "Reduction accumulator is too narrow for the configured maximum length");
    end
    if (($bits(
            memory_port.req_wdata
        ) != DATA_WIDTH) || ($bits(
            memory_port.req_wstrb
        ) != REDUCTION_DATA_BYTES)) begin
      $fatal(1, "Reduction accelerator and memory-interface data widths must match");
    end
  end

  always_comb begin
    signed_mode   = active_flags[FLAG_SIGNED_BIT];
    saturate_mode = active_flags[FLAG_SATURATE_BIT];
    if (elements_remaining > LENGTH_WIDTH'(ELEMENTS_PER_WORD)) begin
      current_word_elements = element_count_t'(ELEMENTS_PER_WORD);
    end else begin
      current_word_elements = element_count_t'(elements_remaining);
    end
    final_word = elements_remaining <= LENGTH_WIDTH'(ELEMENTS_PER_WORD);

    result_write_strobe = '0;
    for (int unsigned byte_index = 0; byte_index < ELEMENT_BYTES; byte_index++) begin
      result_write_strobe[byte_index] = 1'b1;
    end

    for (int unsigned level = 0; level <= TREE_LEVELS; level++) begin
      for (int unsigned node = 0; node < ELEMENTS_PER_WORD; node++) begin
        sum_tree[level][node] = '0;
        if (signed_mode) begin
          max_tree[level][node] = {1'b1, {(ELEMENT_WIDTH - 1) {1'b0}}};
        end else begin
          max_tree[level][node] = '0;
        end
      end
    end

    for (int unsigned lane = 0; lane < ELEMENTS_PER_WORD; lane++) begin
      if (lane < int'(current_word_elements)) begin
        if (signed_mode) begin
          sum_tree[0][lane] = accum_t'($signed(source_word[lane*ELEMENT_WIDTH+:ELEMENT_WIDTH]));
        end else begin
          sum_tree[0][lane] = accum_t'(source_word[lane*ELEMENT_WIDTH+:ELEMENT_WIDTH]);
        end
        max_tree[0][lane] = source_word[lane*ELEMENT_WIDTH+:ELEMENT_WIDTH];
      end
    end

    for (int unsigned level = 0; level < TREE_LEVELS; level++) begin
      for (int unsigned node = 0; node < ELEMENTS_PER_WORD; node++) begin
        if (node < (ELEMENTS_PER_WORD >> (level + 1))) begin
          sum_tree[level+1][node] = sum_tree[level][2*node] + sum_tree[level][(2*node)+1];
          if (signed_mode) begin
            if ($signed(max_tree[level][2*node]) > $signed(max_tree[level][(2*node)+1])) begin
              max_tree[level+1][node] = max_tree[level][2*node];
            end else begin
              max_tree[level+1][node] = max_tree[level][(2*node)+1];
            end
          end else if (max_tree[level][2*node] > max_tree[level][(2*node)+1]) begin
            max_tree[level+1][node] = max_tree[level][2*node];
          end else begin
            max_tree[level+1][node] = max_tree[level][(2*node)+1];
          end
        end
      end
    end

    word_sum = sum_tree[TREE_LEVELS][0];
    word_maximum = max_tree[TREE_LEVELS][0];
    next_accumulator = accumulator;
    if (active_opcode == CMD_OP_REDUCE_SUM) begin
      next_accumulator = accumulator + word_sum;
    end else if (signed_mode) begin
      if ($signed(word_maximum) > $signed(element_t'(accumulator))) begin
        next_accumulator = accum_t'(word_maximum);
      end
    end else if (word_maximum > element_t'(accumulator)) begin
      next_accumulator = accum_t'(word_maximum);
    end

    if (active_opcode == CMD_OP_REDUCE_SUM) begin
      reduced_element = convert_sum(next_accumulator, signed_mode, saturate_mode);
    end else begin
      reduced_element = element_t'(next_accumulator);
    end
    computed_result_word = '0;
    computed_result_word[0+:ELEMENT_WIDTH] = reduced_element;

    source_storage_bytes = byte_count_t'(((int'(command.length) + ELEMENTS_PER_WORD - 1) /
                                          ELEMENTS_PER_WORD) * REDUCTION_DATA_BYTES);
    command_validation_error = ERR_NONE;
    if (!is_reduction_opcode(command.opcode)) begin
      command_validation_error = ERR_OPCODE;
    end else
        if ((command.length == '0) || (command.length > LENGTH_WIDTH'(MAX_REDUCTION_LENGTH))) begin
      command_validation_error = ERR_DIMENSION;
    end else if (!address_is_word_aligned(
            command.src0_addr
        ) || !address_is_word_aligned(
            command.dst_addr
        )) begin
      command_validation_error = ERR_ADDRESS;
    end else if (!scratchpad_range_is_legal(
            command.src0_addr, source_storage_bytes
        ) || !scratchpad_range_is_legal(
            command.dst_addr, byte_count_t'(REDUCTION_DATA_BYTES)
        )) begin
      command_validation_error = ERR_SPM_BOUNDS;
    end

    command_ready = rst_n && (state == REDUCTION_IDLE);
    command_fire = command_valid && command_ready;

    memory_port.req_valid = rst_n &&
        ((state == REDUCTION_READ_REQUEST) || (state == REDUCTION_WRITE_REQUEST));
    memory_port.req_write = state == REDUCTION_WRITE_REQUEST;
    memory_port.req_addr = (state == REDUCTION_WRITE_REQUEST) ? destination_address :
        source_address;
    memory_port.req_wdata = result_word;
    memory_port.req_wstrb = (state == REDUCTION_WRITE_REQUEST) ? result_write_strobe :
        reduction_strb_t'('0);
    memory_port.req_last = final_word || (state == REDUCTION_WRITE_REQUEST);
    memory_port.rsp_ready = rst_n &&
        ((state == REDUCTION_READ_RESPONSE) || (state == REDUCTION_WRITE_RESPONSE));
    memory_request_fire = memory_port.req_valid && memory_port.req_ready;
    memory_response_fire = memory_port.rsp_valid && memory_port.rsp_ready;
    request_wait_state = (state == REDUCTION_READ_REQUEST) || (state == REDUCTION_WRITE_REQUEST);
    response_wait_state = (state == REDUCTION_READ_RESPONSE) || (state == REDUCTION_WRITE_RESPONSE);

    response_valid = state == REDUCTION_RESPONSE;
    response = response_reg;
    busy = state != REDUCTION_IDLE;
    active_cycle = (state != REDUCTION_IDLE) && (state != REDUCTION_RESPONSE);
    stalled_cycle = busy && ((request_wait_state && !memory_port.req_ready) ||
                             (response_wait_state && !memory_port.rsp_valid) ||
                             ((state == REDUCTION_RESPONSE) && !response_ready));
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= REDUCTION_IDLE;
      response_reg <= '0;
      active_opcode <= CMD_OP_INVALID;
      active_flags <= '0;
      active_command_id <= '0;
      active_length <= '0;
      source_address <= '0;
      destination_address <= '0;
      elements_remaining <= '0;
      source_word <= '0;
      result_word <= '0;
      accumulator <= '0;
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
        REDUCTION_IDLE: begin
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
              state <= REDUCTION_RESPONSE;
            end else begin
              source_address <= command.src0_addr;
              destination_address <= command.dst_addr;
              elements_remaining <= command.length;
              if ((command.opcode == CMD_OP_REDUCE_MAX) && command.flags[FLAG_SIGNED_BIT]) begin
                accumulator <= accum_t'({1'b1, {(ELEMENT_WIDTH - 1) {1'b0}}});
              end else begin
                accumulator <= '0;
              end
              state <= REDUCTION_READ_REQUEST;
            end
          end
        end

        REDUCTION_READ_REQUEST: begin
          if (memory_request_fire) begin
            state <= REDUCTION_READ_RESPONSE;
          end
        end

        REDUCTION_READ_RESPONSE: begin
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
              state <= REDUCTION_RESPONSE;
            end else begin
              source_word <= memory_port.rsp_rdata;
              state <= REDUCTION_ACCUMULATE;
            end
          end
        end

        REDUCTION_ACCUMULATE: begin
          accumulator <= next_accumulator;
          if (final_word) begin
            result_word <= computed_result_word;
            state <= REDUCTION_WRITE_REQUEST;
          end else begin
            source_address <= source_address + REDUCTION_DATA_BYTES;
            elements_remaining <= elements_remaining - LENGTH_WIDTH'(ELEMENTS_PER_WORD);
            state <= REDUCTION_READ_REQUEST;
          end
        end

        REDUCTION_WRITE_REQUEST: begin
          if (memory_request_fire) begin
            state <= REDUCTION_WRITE_RESPONSE;
          end
        end

        REDUCTION_WRITE_RESPONSE: begin
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
            end else begin
              response_reg.command_id <= active_command_id;
              response_reg.opcode <= active_opcode;
              response_reg.error <= ERR_NONE;
              response_reg.result <= DATA_WIDTH'(result_word[0+:ELEMENT_WIDTH]);
              response_reg.cycles <= completed_cycle_count(active_cycles);
              done <= 1'b1;
              elements_completed_event <= active_length;
            end
            state <= REDUCTION_RESPONSE;
          end
        end

        REDUCTION_RESPONSE: begin
          if (response_valid && response_ready) begin
            state <= REDUCTION_IDLE;
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
          state <= REDUCTION_RESPONSE;
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
        memory_port.req_addr, byte_count_t'(REDUCTION_DATA_BYTES)
    );
  endproperty

  property p_single_result_write;
    @(posedge clk) disable iff (!rst_n) memory_request_fire &&
        memory_port.req_write |-> final_word && (memory_port.req_wstrb == result_write_strobe);
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
    @(posedge clk) disable iff (!rst_n) state inside {
        REDUCTION_IDLE, REDUCTION_READ_REQUEST, REDUCTION_READ_RESPONSE, REDUCTION_ACCUMULATE,
            REDUCTION_WRITE_REQUEST, REDUCTION_WRITE_RESPONSE, REDUCTION_RESPONSE};
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
  a_single_result_write :
  assert property (p_single_result_write);
  a_done_has_active_command :
  assert property (p_done_has_active_command);
  a_error_implies_done :
  assert property (p_error_implies_done);
  a_state_is_legal :
  assert property (p_state_is_legal);
  a_known_control :
  assert property (p_known_control);

  c_reduce_sum :
  cover property (
      @(posedge clk) disable iff (!rst_n) command_fire && (command.opcode == CMD_OP_REDUCE_SUM));
  c_reduce_max :
  cover property (
      @(posedge clk) disable iff (!rst_n) command_fire && (command.opcode == CMD_OP_REDUCE_MAX));
  c_odd_length :
  cover property (@(posedge clk) disable iff (!rst_n) command_fire && command.length[0]);
  c_signed_operation :
  cover
      property (@(posedge clk) disable iff (!rst_n) command_fire && command.flags[FLAG_SIGNED_BIT]);
  c_saturating_sum :
  cover property (@(posedge clk) disable iff (!rst_n) command_fire &&
                  (command.opcode == CMD_OP_REDUCE_SUM) && command.flags[FLAG_SATURATE_BIT]);
  c_memory_stall :
  cover property (@(posedge clk) disable iff (!rst_n) stalled_cycle);

endmodule
