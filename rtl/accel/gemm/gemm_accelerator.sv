module gemm_accelerator #(
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
  output logic            [accel_pkg::LENGTH_WIDTH-1:0] outputs_completed_event
);

  import accel_pkg::*;
  import soc_pkg::*;

  localparam int unsigned GEMM_DATA_BYTES = DATA_WIDTH / BITS_PER_BYTE;
  localparam int unsigned ELEMENT_BYTES = ELEMENT_WIDTH / BITS_PER_BYTE;
  localparam int unsigned ELEMENTS_PER_WORD = DATA_WIDTH / ELEMENT_WIDTH;
  localparam int unsigned REQUIRED_ACCUM_WIDTH = (2 * ELEMENT_WIDTH) + $clog2(MAX_K) + 1;
  localparam int unsigned TILE_M_INDEX_WIDTH = width_for_index(TILE_M);
  localparam int unsigned TILE_N_INDEX_WIDTH = width_for_index(TILE_N);
  localparam data_t MAXIMUM_CYCLE_COUNT = '1;

  typedef logic [ELEMENT_WIDTH-1:0] element_t;
  typedef logic [DATA_WIDTH-1:0] gemm_word_t;
  typedef logic [GEMM_DATA_BYTES-1:0] gemm_strb_t;
  typedef logic [ACCUM_WIDTH-1:0] accum_t;
  typedef logic signed [ACCUM_WIDTH-1:0] signed_accum_t;

  typedef enum logic [3:0] {
    GEMM_IDLE,
    GEMM_READ_A_REQUEST,
    GEMM_READ_A_RESPONSE,
    GEMM_READ_B_REQUEST,
    GEMM_READ_B_RESPONSE,
    GEMM_MAC,
    GEMM_WRITE_REQUEST,
    GEMM_WRITE_RESPONSE,
    GEMM_RESPONSE
  } gemm_state_e;

  gemm_state_e                                state;
  command_response_t                          response_reg;
  logic              [       FLAGS_WIDTH-1:0] active_flags;
  logic              [  COMMAND_ID_WIDTH-1:0] active_command_id;
  logic              [   DIMENSION_WIDTH-1:0] active_m;
  logic              [   DIMENSION_WIDTH-1:0] active_n;
  logic              [   DIMENSION_WIDTH-1:0] active_k;
  addr_t                                      matrix_a_base;
  addr_t                                      matrix_b_base;
  addr_t                                      matrix_c_base;

  logic              [   DIMENSION_WIDTH-1:0] tile_row_base;
  logic              [   DIMENSION_WIDTH-1:0] tile_column_base;
  logic              [   DIMENSION_WIDTH-1:0] k_index;
  logic              [TILE_M_INDEX_WIDTH-1:0] load_row_index;
  logic              [TILE_N_INDEX_WIDTH-1:0] load_column_index;
  logic              [TILE_M_INDEX_WIDTH-1:0] write_row_index;
  logic              [TILE_N_INDEX_WIDTH-1:0] write_column_index;

  element_t                                   a_values                   [TILE_M];
  element_t                                   b_values                   [TILE_N];
  accum_t                                     tile_accumulators          [TILE_M] [TILE_N];
  logic                                       tile_accumulation_complete;
  logic              [      LENGTH_WIDTH-1:0] outputs_written;
  logic              [      LENGTH_WIDTH-1:0] expected_outputs;
  data_t                                      active_cycles;

  logic                                       signed_mode;
  logic                                       saturate_mode;
  logic              [   DIMENSION_WIDTH-1:0] valid_tile_rows;
  logic              [   DIMENSION_WIDTH-1:0] valid_tile_columns;
  logic                                       command_fire;
  logic                                       memory_request_fire;
  logic                                       memory_response_fire;
  logic                                       request_wait_state;
  logic                                       response_wait_state;
  addr_t                                      current_element_address;
  addr_t                                      current_word_address;
  element_t                                   response_element;
  element_t                                   output_element;
  gemm_word_t                                 output_word;
  gemm_strb_t                                 output_strobe;
  error_e                                     command_validation_error;
  byte_count_t                                matrix_a_storage_bytes;
  byte_count_t                                matrix_b_storage_bytes;
  byte_count_t                                matrix_c_storage_bytes;

  function automatic logic address_is_word_aligned(input addr_t address);
    return (address % GEMM_DATA_BYTES) == '0;
  endfunction

  function automatic addr_t matrix_element_address(
      input addr_t base_address, input logic [DIMENSION_WIDTH-1:0] row,
      input logic [DIMENSION_WIDTH-1:0] stride, input logic [DIMENSION_WIDTH-1:0] column);
    int unsigned element_index;

    element_index = (int'(row) * int'(stride)) + int'(column);
    return base_address + (element_index * ELEMENT_BYTES);
  endfunction

  function automatic addr_t aligned_word_address(input addr_t element_address);
    return element_address - (element_address % GEMM_DATA_BYTES);
  endfunction

  function automatic element_t select_element(input gemm_word_t word, input addr_t element_address);
    int unsigned lane;

    lane = (int'(element_address % GEMM_DATA_BYTES)) / ELEMENT_BYTES;
    return word[lane*ELEMENT_WIDTH+:ELEMENT_WIDTH];
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

  function automatic logic ranges_overlap(
      input addr_t first_address, input byte_count_t first_length, input addr_t second_address,
      input byte_count_t second_length);
    logic [ADDR_WIDTH:0] first_end;
    logic [ADDR_WIDTH:0] second_end;

    first_end  = {1'b0, first_address} + (ADDR_WIDTH + 1)'(first_length);
    second_end = {1'b0, second_address} + (ADDR_WIDTH + 1)'(second_length);
    return ({1'b0, first_address} < second_end) && ({1'b0, second_address} < first_end);
  endfunction

  function automatic byte_count_t matrix_storage_bytes(input logic [DIMENSION_WIDTH-1:0] rows,
                                                       input logic [DIMENSION_WIDTH-1:0] columns);
    int unsigned raw_bytes;
    int unsigned word_count;

    raw_bytes  = int'(rows) * int'(columns) * ELEMENT_BYTES;
    word_count = (raw_bytes + GEMM_DATA_BYTES - 1) / GEMM_DATA_BYTES;
    return byte_count_t'(word_count * GEMM_DATA_BYTES);
  endfunction

  function automatic accum_t multiply_elements(input element_t lhs, input element_t rhs,
                                               input logic use_signed);
    signed_accum_t signed_lhs;
    signed_accum_t signed_rhs;
    signed_accum_t signed_product;
    accum_t        unsigned_lhs;
    accum_t        unsigned_rhs;

    signed_lhs = signed_accum_t'($signed(lhs));
    signed_rhs = signed_accum_t'($signed(rhs));
    signed_product = signed_lhs * signed_rhs;
    unsigned_lhs = accum_t'(lhs);
    unsigned_rhs = accum_t'(rhs);
    if (use_signed) begin
      return accum_t'(signed_product);
    end
    return unsigned_lhs * unsigned_rhs;
  endfunction

  function automatic element_t convert_accumulator(input accum_t value, input logic use_signed,
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

  function automatic data_t completed_cycle_count(input data_t cycle_count);
    return (cycle_count == MAXIMUM_CYCLE_COUNT) ? MAXIMUM_CYCLE_COUNT : cycle_count + 1'b1;
  endfunction

  initial begin : validate_parameters
    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % BITS_PER_BYTE) != 0)) begin
      $fatal(1, "GEMM data width must contain a positive whole number of bytes");
    end
    if ((ELEMENT_WIDTH == 0) || ((ELEMENT_WIDTH % BITS_PER_BYTE) != 0) ||
        ((DATA_WIDTH % ELEMENT_WIDTH) != 0)) begin
      $fatal(1, "GEMM element width must byte-align and divide the memory data width");
    end
    if ((GEMM_DATA_BYTES & (GEMM_DATA_BYTES - 1)) != 0) begin
      $fatal(1, "GEMM memory word must contain a power-of-two byte count");
    end
    if ((MAX_M == 0) || (MAX_N == 0) || (MAX_K == 0) || (TILE_M == 0) || (TILE_N == 0) ||
        (TILE_M > MAX_M) || (TILE_N > MAX_N)) begin
      $fatal(1, "GEMM dimensions and tile sizes must be positive and ordered");
    end
    if ((MAX_M > ((1 << DIMENSION_WIDTH) - 1)) || (MAX_N > ((1 << DIMENSION_WIDTH) - 1)) ||
        (MAX_K > ((1 << DIMENSION_WIDTH) - 1))) begin
      $fatal(1, "GEMM maximum dimensions must fit the descriptor fields");
    end
    if (ACCUM_WIDTH < REQUIRED_ACCUM_WIDTH) begin
      $fatal(1, "GEMM accumulator is too narrow for the configured maximum K");
    end
    if (($bits(
            memory_port.req_wdata
        ) != DATA_WIDTH) || ($bits(
            memory_port.req_wstrb
        ) != GEMM_DATA_BYTES)) begin
      $fatal(1, "GEMM accelerator and memory-interface data widths must match");
    end
  end

  always_comb begin
    signed_mode   = active_flags[FLAG_SIGNED_BIT];
    saturate_mode = active_flags[FLAG_SATURATE_BIT];

    if ((active_m - tile_row_base) > DIMENSION_WIDTH'(TILE_M)) begin
      valid_tile_rows = DIMENSION_WIDTH'(TILE_M);
    end else begin
      valid_tile_rows = active_m - tile_row_base;
    end
    if ((active_n - tile_column_base) > DIMENSION_WIDTH'(TILE_N)) begin
      valid_tile_columns = DIMENSION_WIDTH'(TILE_N);
    end else begin
      valid_tile_columns = active_n - tile_column_base;
    end

    current_element_address = matrix_element_address(
        matrix_a_base, tile_row_base + DIMENSION_WIDTH'(load_row_index), active_k, k_index);
    if ((state == GEMM_READ_B_REQUEST) || (state == GEMM_READ_B_RESPONSE)) begin
      current_element_address = matrix_element_address(
          matrix_b_base, k_index, active_n, tile_column_base + DIMENSION_WIDTH'(load_column_index));
    end else if ((state == GEMM_WRITE_REQUEST) || (state == GEMM_WRITE_RESPONSE)) begin
      current_element_address = matrix_element_address(
        matrix_c_base,
        tile_row_base + DIMENSION_WIDTH'(write_row_index),
        active_n,
        tile_column_base + DIMENSION_WIDTH'(write_column_index)
      );
    end
    current_word_address = aligned_word_address(current_element_address);
    response_element = select_element(memory_port.rsp_rdata, current_element_address);

    output_element = convert_accumulator(tile_accumulators[write_row_index][write_column_index],
                                         signed_mode, saturate_mode);
    output_word = '0;
    output_strobe = '0;
    for (int unsigned lane = 0; lane < ELEMENTS_PER_WORD; lane++) begin
      if ((current_element_address % GEMM_DATA_BYTES) == (lane * ELEMENT_BYTES)) begin
        output_word[lane*ELEMENT_WIDTH+:ELEMENT_WIDTH] = output_element;
        for (int unsigned element_byte = 0; element_byte < ELEMENT_BYTES; element_byte++) begin
          output_strobe[(lane*ELEMENT_BYTES)+element_byte] = 1'b1;
        end
      end
    end

    matrix_a_storage_bytes   = matrix_storage_bytes(command.m, command.k);
    matrix_b_storage_bytes   = matrix_storage_bytes(command.k, command.n);
    matrix_c_storage_bytes   = matrix_storage_bytes(command.m, command.n);
    command_validation_error = ERR_NONE;
    if (command.opcode != CMD_OP_GEMM) begin
      command_validation_error = ERR_OPCODE;
    end else if ((command.m == '0) || (command.n == '0) || (command.k == '0) ||
                 (command.m > DIMENSION_WIDTH'(MAX_M)) || (command.n > DIMENSION_WIDTH'(MAX_N)) ||
                 (command.k > DIMENSION_WIDTH'(MAX_K))) begin
      command_validation_error = ERR_DIMENSION;
    end else if (!address_is_word_aligned(
            command.src0_addr
        ) || !address_is_word_aligned(
            command.src1_addr
        ) || !address_is_word_aligned(
            command.dst_addr
        )) begin
      command_validation_error = ERR_ADDRESS;
    end else if (!scratchpad_range_is_legal(
            command.src0_addr, matrix_a_storage_bytes
        ) || !scratchpad_range_is_legal(
            command.src1_addr, matrix_b_storage_bytes
        ) || !scratchpad_range_is_legal(
            command.dst_addr, matrix_c_storage_bytes
        )) begin
      command_validation_error = ERR_SPM_BOUNDS;
    end else if (ranges_overlap(
            command.dst_addr, matrix_c_storage_bytes, command.src0_addr, matrix_a_storage_bytes
        ) || ranges_overlap(
            command.dst_addr, matrix_c_storage_bytes, command.src1_addr, matrix_b_storage_bytes
        )) begin
      command_validation_error = ERR_ADDRESS;
    end

    command_ready = rst_n && (state == GEMM_IDLE);
    command_fire = command_valid && command_ready;

    memory_port.req_valid = rst_n &&
        ((state == GEMM_READ_A_REQUEST) || (state == GEMM_READ_B_REQUEST) ||
         (state == GEMM_WRITE_REQUEST));
    memory_port.req_write = state == GEMM_WRITE_REQUEST;
    memory_port.req_addr = current_word_address;
    memory_port.req_wdata = output_word;
    memory_port.req_wstrb = (state == GEMM_WRITE_REQUEST) ? output_strobe : gemm_strb_t'('0);
    memory_port.req_last = (state == GEMM_WRITE_REQUEST) &&
        ((outputs_written + 1'b1) == expected_outputs);
    memory_port.rsp_ready = rst_n &&
        ((state == GEMM_READ_A_RESPONSE) || (state == GEMM_READ_B_RESPONSE) ||
         (state == GEMM_WRITE_RESPONSE));
    memory_request_fire = memory_port.req_valid && memory_port.req_ready;
    memory_response_fire = memory_port.rsp_valid && memory_port.rsp_ready;
    request_wait_state = (state == GEMM_READ_A_REQUEST) || (state == GEMM_READ_B_REQUEST) ||
        (state == GEMM_WRITE_REQUEST);
    response_wait_state = (state == GEMM_READ_A_RESPONSE) || (state == GEMM_READ_B_RESPONSE) ||
        (state == GEMM_WRITE_RESPONSE);

    response_valid = state == GEMM_RESPONSE;
    response = response_reg;
    busy = state != GEMM_IDLE;
    active_cycle = (state != GEMM_IDLE) && (state != GEMM_RESPONSE);
    stalled_cycle = busy && ((request_wait_state && !memory_port.req_ready) ||
                             (response_wait_state && !memory_port.rsp_valid) ||
                             ((state == GEMM_RESPONSE) && !response_ready));
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= GEMM_IDLE;
      response_reg <= '0;
      active_flags <= '0;
      active_command_id <= '0;
      active_m <= '0;
      active_n <= '0;
      active_k <= '0;
      matrix_a_base <= '0;
      matrix_b_base <= '0;
      matrix_c_base <= '0;
      tile_row_base <= '0;
      tile_column_base <= '0;
      k_index <= '0;
      load_row_index <= '0;
      load_column_index <= '0;
      write_row_index <= '0;
      write_column_index <= '0;
      tile_accumulation_complete <= 1'b0;
      outputs_written <= '0;
      expected_outputs <= '0;
      active_cycles <= '0;
      done <= 1'b0;
      error <= 1'b0;
      error_code <= ERR_NONE;
      outputs_completed_event <= '0;
      for (int unsigned row = 0; row < TILE_M; row++) begin
        a_values[row] <= '0;
        for (int unsigned column = 0; column < TILE_N; column++) begin
          tile_accumulators[row][column] <= '0;
        end
      end
      for (int unsigned column = 0; column < TILE_N; column++) begin
        b_values[column] <= '0;
      end
    end else begin
      done <= 1'b0;
      error <= 1'b0;
      error_code <= ERR_NONE;
      outputs_completed_event <= '0;
      if (active_cycle && (active_cycles != MAXIMUM_CYCLE_COUNT)) begin
        active_cycles <= active_cycles + 1'b1;
      end

      unique case (state)
        GEMM_IDLE: begin
          active_cycles <= '0;
          if (command_fire) begin
            active_flags <= command.flags;
            active_command_id <= command.command_id;
            active_m <= command.m;
            active_n <= command.n;
            active_k <= command.k;
            matrix_a_base <= command.src0_addr;
            matrix_b_base <= command.src1_addr;
            matrix_c_base <= command.dst_addr;
            expected_outputs <= LENGTH_WIDTH'(int'(command.m) * int'(command.n));
            outputs_written <= '0;
            tile_row_base <= '0;
            tile_column_base <= '0;
            k_index <= '0;
            load_row_index <= '0;
            load_column_index <= '0;
            write_row_index <= '0;
            write_column_index <= '0;
            tile_accumulation_complete <= 1'b0;
            for (int unsigned row = 0; row < TILE_M; row++) begin
              for (int unsigned column = 0; column < TILE_N; column++) begin
                tile_accumulators[row][column] <= '0;
              end
            end
            if (command_validation_error != ERR_NONE) begin
              response_reg.command_id <= command.command_id;
              response_reg.opcode <= command.opcode;
              response_reg.error <= command_validation_error;
              response_reg.result <= '0;
              response_reg.cycles <= '0;
              done <= 1'b1;
              error <= 1'b1;
              error_code <= command_validation_error;
              state <= GEMM_RESPONSE;
            end else begin
              state <= GEMM_READ_A_REQUEST;
            end
          end
        end

        GEMM_READ_A_REQUEST: begin
          if (memory_request_fire) begin
            state <= GEMM_READ_A_RESPONSE;
          end
        end

        GEMM_READ_A_RESPONSE: begin
          if (memory_response_fire) begin
            if (memory_port.rsp_error) begin
              response_reg.command_id <= active_command_id;
              response_reg.opcode <= CMD_OP_GEMM;
              response_reg.error <= ERR_ADDRESS;
              response_reg.result <= '0;
              response_reg.cycles <= completed_cycle_count(active_cycles);
              done <= 1'b1;
              error <= 1'b1;
              error_code <= ERR_ADDRESS;
              state <= GEMM_RESPONSE;
            end else begin
              a_values[load_row_index] <= response_element;
              if ((DIMENSION_WIDTH'(load_row_index) + 1'b1) >= valid_tile_rows) begin
                load_column_index <= '0;
                state <= GEMM_READ_B_REQUEST;
              end else begin
                load_row_index <= load_row_index + 1'b1;
                state <= GEMM_READ_A_REQUEST;
              end
            end
          end
        end

        GEMM_READ_B_REQUEST: begin
          if (memory_request_fire) begin
            state <= GEMM_READ_B_RESPONSE;
          end
        end

        GEMM_READ_B_RESPONSE: begin
          if (memory_response_fire) begin
            if (memory_port.rsp_error) begin
              response_reg.command_id <= active_command_id;
              response_reg.opcode <= CMD_OP_GEMM;
              response_reg.error <= ERR_ADDRESS;
              response_reg.result <= '0;
              response_reg.cycles <= completed_cycle_count(active_cycles);
              done <= 1'b1;
              error <= 1'b1;
              error_code <= ERR_ADDRESS;
              state <= GEMM_RESPONSE;
            end else begin
              b_values[load_column_index] <= response_element;
              if ((DIMENSION_WIDTH'(load_column_index) + 1'b1) >= valid_tile_columns) begin
                state <= GEMM_MAC;
              end else begin
                load_column_index <= load_column_index + 1'b1;
                state <= GEMM_READ_B_REQUEST;
              end
            end
          end
        end

        GEMM_MAC: begin
          for (int unsigned row = 0; row < TILE_M; row++) begin
            for (int unsigned column = 0; column < TILE_N; column++) begin
              if ((row < int'(valid_tile_rows)) && (column < int'(valid_tile_columns))) begin
                tile_accumulators[row][column] <= tile_accumulators[row][column] +
                    multiply_elements(a_values[row], b_values[column], signed_mode);
              end
            end
          end
          if ((k_index + 1'b1) < active_k) begin
            k_index <= k_index + 1'b1;
            load_row_index <= '0;
            state <= GEMM_READ_A_REQUEST;
          end else begin
            write_row_index <= '0;
            write_column_index <= '0;
            tile_accumulation_complete <= 1'b1;
            state <= GEMM_WRITE_REQUEST;
          end
        end

        GEMM_WRITE_REQUEST: begin
          if (memory_request_fire) begin
            state <= GEMM_WRITE_RESPONSE;
          end
        end

        GEMM_WRITE_RESPONSE: begin
          if (memory_response_fire) begin
            if (memory_port.rsp_error) begin
              response_reg.command_id <= active_command_id;
              response_reg.opcode <= CMD_OP_GEMM;
              response_reg.error <= ERR_ADDRESS;
              response_reg.result <= '0;
              response_reg.cycles <= completed_cycle_count(active_cycles);
              done <= 1'b1;
              error <= 1'b1;
              error_code <= ERR_ADDRESS;
              state <= GEMM_RESPONSE;
            end else begin
              outputs_written <= outputs_written + 1'b1;
              outputs_completed_event <= LENGTH_WIDTH'(1);
              if ((DIMENSION_WIDTH'(write_column_index) + 1'b1) < valid_tile_columns) begin
                write_column_index <= write_column_index + 1'b1;
                state <= GEMM_WRITE_REQUEST;
              end else if ((DIMENSION_WIDTH'(write_row_index) + 1'b1) < valid_tile_rows) begin
                write_row_index <= write_row_index + 1'b1;
                write_column_index <= '0;
                state <= GEMM_WRITE_REQUEST;
              end else begin
                tile_accumulation_complete <= 1'b0;
                if ((outputs_written + 1'b1) == expected_outputs) begin
                  response_reg.command_id <= active_command_id;
                  response_reg.opcode <= CMD_OP_GEMM;
                  response_reg.error <= ERR_NONE;
                  response_reg.result <= DATA_WIDTH'(expected_outputs);
                  response_reg.cycles <= completed_cycle_count(active_cycles);
                  done <= 1'b1;
                  state <= GEMM_RESPONSE;
                end else begin
                  if ((tile_column_base + valid_tile_columns) >= active_n) begin
                    tile_column_base <= '0;
                    tile_row_base <= tile_row_base + DIMENSION_WIDTH'(TILE_M);
                  end else begin
                    tile_column_base <= tile_column_base + DIMENSION_WIDTH'(TILE_N);
                  end
                  k_index <= '0;
                  load_row_index <= '0;
                  load_column_index <= '0;
                  for (int unsigned row = 0; row < TILE_M; row++) begin
                    for (int unsigned column = 0; column < TILE_N; column++) begin
                      tile_accumulators[row][column] <= '0;
                    end
                  end
                  state <= GEMM_READ_A_REQUEST;
                end
              end
            end
          end
        end

        GEMM_RESPONSE: begin
          if (response_valid && response_ready) begin
            state <= GEMM_IDLE;
          end
        end

        default: begin
          response_reg.command_id <= active_command_id;
          response_reg.opcode <= CMD_OP_GEMM;
          response_reg.error <= ERR_INTERNAL;
          response_reg.result <= '0;
          response_reg.cycles <= active_cycles;
          done <= 1'b1;
          error <= 1'b1;
          error_code <= ERR_INTERNAL;
          state <= GEMM_RESPONSE;
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
        memory_port.req_addr, byte_count_t'(GEMM_DATA_BYTES)
    );
  endproperty

  property p_no_write_before_accumulation;
    @(posedge clk) disable iff (!rst_n) memory_port.req_valid &&
        memory_port.req_write |-> tile_accumulation_complete;
  endproperty

  property p_write_index_in_tile;
    @(posedge clk) disable iff (!rst_n) memory_port.req_valid &&
        memory_port.req_write |-> (DIMENSION_WIDTH'(write_row_index) < valid_tile_rows) &&
        (DIMENSION_WIDTH'(write_column_index) < valid_tile_columns);
  endproperty

  property p_output_count_in_range;
    @(posedge clk) disable iff (!rst_n) outputs_written <= expected_outputs;
  endproperty

  property p_success_done_after_all_outputs;
    @(posedge clk) disable iff (!rst_n) done && !error |-> outputs_written == expected_outputs;
  endproperty

  property p_error_implies_done;
    @(posedge clk) disable iff (!rst_n) error |-> done && (error_code != ERR_NONE);
  endproperty

  property p_state_is_legal;
    @(posedge clk) disable iff (!rst_n) state inside {
        GEMM_IDLE, GEMM_READ_A_REQUEST, GEMM_READ_A_RESPONSE, GEMM_READ_B_REQUEST,
            GEMM_READ_B_RESPONSE, GEMM_MAC, GEMM_WRITE_REQUEST, GEMM_WRITE_RESPONSE, GEMM_RESPONSE};
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
  a_no_write_before_accumulation :
  assert property (p_no_write_before_accumulation);
  a_write_index_in_tile :
  assert property (p_write_index_in_tile);
  a_output_count_in_range :
  assert property (p_output_count_in_range);
  a_success_done_after_all_outputs :
  assert property (p_success_done_after_all_outputs);
  a_error_implies_done :
  assert property (p_error_implies_done);
  a_state_is_legal :
  assert property (p_state_is_legal);
  a_known_control :
  assert property (p_known_control);

  c_single_element :
  cover property (@(posedge clk) disable iff (!rst_n) command_fire && (command.m == 1) &&
                  (command.n == 1) && (command.k == 1));
  c_rectangular :
  cover property (@(posedge clk) disable iff (!rst_n) command_fire &&
                  ((command.m != command.n) || (command.n != command.k)));
  c_partial_tile :
  cover property (@(posedge clk) disable iff (!rst_n) command_fire &&
                  (((int'(command.m) % TILE_M) != 0) || ((int'(command.n) % TILE_N) != 0)));
  c_signed_operation :
  cover
      property (@(posedge clk) disable iff (!rst_n) command_fire && command.flags[FLAG_SIGNED_BIT]);
  c_saturating_operation :
  cover property (
      @(posedge clk) disable iff (!rst_n) command_fire && command.flags[FLAG_SATURATE_BIT]);
  c_memory_stall :
  cover property (@(posedge clk) disable iff (!rst_n) stalled_cycle);

endmodule
