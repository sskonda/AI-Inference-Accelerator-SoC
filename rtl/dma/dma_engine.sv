module dma_engine #(
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH,
    parameter int unsigned MAX_BURST_BEATS = soc_pkg::DEFAULT_DMA_BURST_BEATS
) (
  input logic clk,
  input logic rst_n,

  input  logic                 start,
  input  soc_pkg::addr_t       source_address,
  input  soc_pkg::addr_t       destination_address,
  input  soc_pkg::byte_count_t length_bytes,
  output logic                 start_accepted,
  output logic                 start_rejected,
  output logic                 busy,
  output logic                 done,
  output logic                 error,
  output soc_pkg::error_e      error_code,

  mem_if.initiator source_port,
  mem_if.initiator destination_port,

  output logic                 active_cycle,
  output logic                 stalled_cycle,
  output soc_pkg::byte_count_t bytes_read_event,
  output soc_pkg::byte_count_t bytes_written_event
);

  import soc_pkg::*;

  localparam int unsigned DMA_DATA_BYTES = DATA_WIDTH / BITS_PER_BYTE;
  localparam int unsigned DMA_STRB_WIDTH = DMA_DATA_BYTES;
  localparam int unsigned BURST_INDEX_WIDTH = width_for_index(MAX_BURST_BEATS);

  typedef logic [DMA_STRB_WIDTH-1:0] dma_strb_t;

  typedef enum logic [2:0] {
    DMA_IDLE,
    DMA_READ_REQUEST,
    DMA_READ_RESPONSE,
    DMA_WRITE_REQUEST,
    DMA_WRITE_RESPONSE
  } dma_state_e;

  dma_state_e                          state;
  addr_t                               current_source_address;
  addr_t                               current_destination_address;
  byte_count_t                         bytes_remaining;
  logic        [       DATA_WIDTH-1:0] read_data;
  logic        [BURST_INDEX_WIDTH-1:0] burst_index;
  byte_count_t                         current_beat_bytes;
  dma_strb_t                           current_write_strobe;
  logic                                current_burst_last;
  logic                                source_response_fire;
  logic                                destination_response_fire;
  logic                                source_terminal_error;
  logic                                destination_terminal;
  logic                                source_range_legal;
  logic                                destination_range_legal;
  logic                                start_ranges_overlap;
  logic                                start_address_error;

  function automatic logic address_is_aligned(input addr_t address);
    return (address % DMA_DATA_BYTES) == '0;
  endfunction

  function automatic dma_strb_t byte_strobe(input byte_count_t byte_count);
    dma_strb_t strobe;

    strobe = '0;
    for (int unsigned byte_index = 0; byte_index < DMA_DATA_BYTES; byte_index++) begin
      if (byte_count > byte_count_t'(byte_index)) begin
        strobe[byte_index] = 1'b1;
      end
    end
    return strobe;
  endfunction

  function automatic logic ranges_overlap(input addr_t first_address, input addr_t second_address,
                                          input byte_count_t byte_count);
    logic [ADDR_WIDTH:0] first_end;
    logic [ADDR_WIDTH:0] second_end;

    first_end  = {1'b0, first_address} + (ADDR_WIDTH + 1)'(byte_count);
    second_end = {1'b0, second_address} + (ADDR_WIDTH + 1)'(byte_count);
    return (byte_count != '0) && (first_address != second_address) &&
        ({1'b0, first_address} < second_end) && ({1'b0, second_address} < first_end);
  endfunction

  initial begin : validate_parameters
    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % BITS_PER_BYTE) != 0)) begin
      $fatal(1, "DMA data width must contain a positive whole number of bytes");
    end
    if ((DMA_DATA_BYTES & (DMA_DATA_BYTES - 1)) != 0) begin
      $fatal(1, "DMA data word must contain a power-of-two byte count");
    end
    if (MAX_BURST_BEATS == 0) begin
      $fatal(1, "DMA maximum burst length must be positive");
    end
    if (($bits(
            source_port.req_wdata
        ) != DATA_WIDTH) || ($bits(
            destination_port.req_wdata
        ) != DATA_WIDTH) || ($bits(
            destination_port.req_wstrb
        ) != DMA_STRB_WIDTH)) begin
      $fatal(1, "DMA and memory-interface data widths must match");
    end
  end

  always_comb begin
    source_range_legal = data_range_is_legal(source_address, length_bytes);
    destination_range_legal = data_range_is_legal(destination_address, length_bytes);
    start_ranges_overlap = source_range_legal && destination_range_legal &&
        ranges_overlap(source_address, destination_address, length_bytes);
    start_address_error = !address_is_aligned(source_address) ||
        !address_is_aligned(destination_address) || !source_range_legal ||
        !destination_range_legal || start_ranges_overlap;

    if (bytes_remaining > byte_count_t'(DMA_DATA_BYTES)) begin
      current_beat_bytes = byte_count_t'(DMA_DATA_BYTES);
    end else begin
      current_beat_bytes = bytes_remaining;
    end
    current_write_strobe = byte_strobe(current_beat_bytes);
    current_burst_last = (burst_index == BURST_INDEX_WIDTH'(MAX_BURST_BEATS - 1)) ||
        (bytes_remaining <= byte_count_t'(DMA_DATA_BYTES));

    source_port.req_valid = rst_n && (state == DMA_READ_REQUEST);
    source_port.req_write = 1'b0;
    source_port.req_addr = current_source_address;
    source_port.req_wdata = '0;
    source_port.req_wstrb = '0;
    source_port.req_last = source_port.req_valid && current_burst_last;
    source_port.rsp_ready = rst_n && (state == DMA_READ_RESPONSE);

    destination_port.req_valid = rst_n && (state == DMA_WRITE_REQUEST);
    destination_port.req_write = 1'b1;
    destination_port.req_addr = current_destination_address;
    destination_port.req_wdata = read_data;
    destination_port.req_wstrb = current_write_strobe;
    destination_port.req_last = destination_port.req_valid && current_burst_last;
    destination_port.rsp_ready = rst_n && (state == DMA_WRITE_RESPONSE);

    source_response_fire = source_port.rsp_valid && source_port.rsp_ready;
    destination_response_fire = destination_port.rsp_valid && destination_port.rsp_ready;
    source_terminal_error = source_response_fire && source_port.rsp_error;
    destination_terminal = destination_response_fire &&
        (destination_port.rsp_error || (bytes_remaining <= byte_count_t'(DMA_DATA_BYTES)));

    active_cycle = busy;
    stalled_cycle = busy && (((state == DMA_READ_REQUEST) && !source_port.req_ready) ||
                             ((state == DMA_READ_RESPONSE) && !source_port.rsp_valid) ||
                             ((state == DMA_WRITE_REQUEST) && !destination_port.req_ready) ||
                             ((state == DMA_WRITE_RESPONSE) && !destination_port.rsp_valid));
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= DMA_IDLE;
      busy <= 1'b0;
      done <= 1'b0;
      error <= 1'b0;
      error_code <= ERR_NONE;
      start_accepted <= 1'b0;
      start_rejected <= 1'b0;
      bytes_read_event <= '0;
      bytes_written_event <= '0;
    end else begin
      done <= 1'b0;
      error <= 1'b0;
      error_code <= ERR_NONE;
      start_accepted <= 1'b0;
      start_rejected <= 1'b0;
      bytes_read_event <= '0;
      bytes_written_event <= '0;

      if (start && busy) begin
        start_rejected <= 1'b1;
        error <= 1'b1;
        error_code <= ERR_DMA_BUSY;
      end

      unique case (state)
        DMA_IDLE: begin
          busy <= 1'b0;
          if (start) begin
            start_accepted <= 1'b1;
            if (length_bytes == '0) begin
              done <= 1'b1;
            end else if (start_address_error) begin
              done <= 1'b1;
              error <= 1'b1;
              error_code <= ERR_ADDRESS;
            end else begin
              current_source_address <= source_address;
              current_destination_address <= destination_address;
              bytes_remaining <= length_bytes;
              burst_index <= '0;
              busy <= 1'b1;
              state <= DMA_READ_REQUEST;
            end
          end
        end

        DMA_READ_REQUEST: begin
          if (source_port.req_valid && source_port.req_ready) begin
            state <= DMA_READ_RESPONSE;
          end
        end

        DMA_READ_RESPONSE: begin
          if (source_response_fire) begin
            if (source_port.rsp_error) begin
              busy <= 1'b0;
              done <= 1'b1;
              error <= 1'b1;
              error_code <= ERR_ADDRESS;
              state <= DMA_IDLE;
            end else begin
              read_data <= source_port.rsp_rdata;
              bytes_read_event <= current_beat_bytes;
              state <= DMA_WRITE_REQUEST;
            end
          end
        end

        DMA_WRITE_REQUEST: begin
          if (destination_port.req_valid && destination_port.req_ready) begin
            state <= DMA_WRITE_RESPONSE;
          end
        end

        DMA_WRITE_RESPONSE: begin
          if (destination_response_fire) begin
            if (destination_port.rsp_error) begin
              busy <= 1'b0;
              done <= 1'b1;
              error <= 1'b1;
              error_code <= ERR_ADDRESS;
              state <= DMA_IDLE;
            end else begin
              bytes_written_event <= current_beat_bytes;
              if (bytes_remaining <= byte_count_t'(DMA_DATA_BYTES)) begin
                busy  <= 1'b0;
                done  <= 1'b1;
                state <= DMA_IDLE;
              end else begin
                current_source_address <= current_source_address + DMA_DATA_BYTES;
                current_destination_address <= current_destination_address + DMA_DATA_BYTES;
                bytes_remaining <= bytes_remaining - byte_count_t'(DMA_DATA_BYTES);
                if (current_burst_last) begin
                  burst_index <= '0;
                end else begin
                  burst_index <= burst_index + 1'b1;
                end
                state <= DMA_READ_REQUEST;
              end
            end
          end
        end

        default: begin
          state <= DMA_IDLE;
          busy <= 1'b0;
          done <= 1'b1;
          error <= 1'b1;
          error_code <= ERR_INTERNAL;
        end
      endcase
    end
  end

  property p_busy_matches_active_state;
    @(posedge clk) disable iff (!rst_n) (state != DMA_IDLE) |-> busy;
  endproperty

  property p_busy_remains_until_terminal;
    @(posedge clk) disable iff (!rst_n) busy && !source_terminal_error &&
        !destination_terminal |=> busy;
  endproperty

  property p_done_is_single_cycle;
    @(posedge clk) disable iff (!rst_n) done |=> !done || start_accepted;
  endproperty

  property p_error_is_single_cycle;
    @(posedge clk) disable iff (!rst_n) error |=> !error || start_accepted || start_rejected;
  endproperty

  property p_done_follows_start_or_activity;
    @(posedge clk) disable iff (!rst_n) done |-> start_accepted || $past(
        busy
    );
  endproperty

  property p_start_while_busy_is_rejected;
    @(posedge clk) disable iff (!rst_n) start && busy |=> start_rejected;
  endproperty

  property p_start_address_error_rejects_before_traffic;
    @(posedge clk) disable iff (!rst_n) start && (state == DMA_IDLE) && (length_bytes != '0) &&
        start_address_error |=> done && error && (error_code == ERR_ADDRESS) && !busy &&
        !source_port.req_valid && !destination_port.req_valid;
  endproperty

  property p_read_within_remaining_length;
    @(posedge clk) disable iff (!rst_n) source_port.req_valid && source_port.req_ready |->
        (bytes_remaining != '0) && (current_beat_bytes <= bytes_remaining) && data_range_is_legal(
        source_port.req_addr, current_beat_bytes
    );
  endproperty

  property p_write_within_remaining_length;
    @(posedge clk) disable iff (!rst_n) destination_port.req_valid && destination_port.req_ready |->
        (bytes_remaining != '0) && (current_beat_bytes <= bytes_remaining) && data_range_is_legal(
        destination_port.req_addr, current_beat_bytes
    ) && (destination_port.req_wstrb == current_write_strobe);
  endproperty

  property p_write_follows_successful_read;
    @(posedge clk) disable iff (!rst_n) destination_port.req_valid && !$past(
        destination_port.req_valid
    ) |-> $past(
        source_response_fire && !source_port.rsp_error
    );
  endproperty

  property p_known_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {
          state,
          busy,
          done,
          error,
          start_accepted,
          start_rejected,
          source_port.req_valid,
          source_port.rsp_ready,
          destination_port.req_valid,
          destination_port.rsp_ready
        }
    );
  endproperty

  property p_successful_done_follows_final_write;
    @(posedge clk) disable iff (!rst_n) done && !error && !start_accepted |-> $past(
        destination_response_fire && !destination_port.rsp_error &&
            (bytes_remaining <= byte_count_t'(DMA_DATA_BYTES))
    );
  endproperty

  property p_burst_index_in_range;
    @(posedge clk) disable iff (!rst_n)
        busy |-> burst_index <= BURST_INDEX_WIDTH'(MAX_BURST_BEATS - 1);
  endproperty

  a_busy_matches_active_state :
  assert property (p_busy_matches_active_state);
  a_busy_remains_until_terminal :
  assert property (p_busy_remains_until_terminal);
  a_done_is_single_cycle :
  assert property (p_done_is_single_cycle);
  a_error_is_single_cycle :
  assert property (p_error_is_single_cycle);
  a_done_follows_start_or_activity :
  assert property (p_done_follows_start_or_activity);
  a_start_while_busy_is_rejected :
  assert property (p_start_while_busy_is_rejected);
  a_start_address_error_rejects_before_traffic :
  assert property (p_start_address_error_rejects_before_traffic);
  a_read_within_remaining_length :
  assert property (p_read_within_remaining_length);
  a_write_within_remaining_length :
  assert property (p_write_within_remaining_length);
  a_write_follows_successful_read :
  assert property (p_write_follows_successful_read);
  a_known_control :
  assert property (p_known_control);
  a_successful_done_follows_final_write :
  assert property (p_successful_done_follows_final_write);
  a_burst_index_in_range :
  assert property (p_burst_index_in_range);

endmodule
