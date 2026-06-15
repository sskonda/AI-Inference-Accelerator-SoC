module soc_memory_fabric #(
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH
) (
  input logic clk,
  input logic rst_n,

  mem_if.target    dma_source_port,
  mem_if.target    dma_destination_port,
  mem_if.target    vector_port,
  mem_if.target    reduction_port,
  mem_if.target    gemm_port,
  mem_if.initiator external_port,

  output logic busy,
  output logic error_event
);

  import soc_pkg::*;

  localparam int unsigned REQUESTER_COUNT = 5;
  localparam int unsigned OWNER_WIDTH = width_for_index(REQUESTER_COUNT);
  localparam int unsigned FABRIC_DATA_BYTES = DATA_WIDTH / BITS_PER_BYTE;

  typedef logic [OWNER_WIDTH-1:0] owner_t;
  typedef logic [FABRIC_DATA_BYTES-1:0] fabric_strb_t;
  typedef enum logic [2:0] {
    FABRIC_IDLE,
    FABRIC_REQUEST,
    FABRIC_SPM_READ_WAIT,
    FABRIC_LOCAL_RESPONSE,
    FABRIC_EXTERNAL_RESPONSE
  } fabric_state_e;

  localparam owner_t OWNER_DMA_SOURCE = owner_t'(0);
  localparam owner_t OWNER_DMA_DESTINATION = owner_t'(1);
  localparam owner_t OWNER_VECTOR = owner_t'(2);
  localparam owner_t OWNER_REDUCTION = owner_t'(3);
  localparam owner_t OWNER_GEMM = owner_t'(4);
  localparam owner_t LAST_OWNER = owner_t'(REQUESTER_COUNT - 1);

  fabric_state_e                       state;
  owner_t                              transaction_owner;
  owner_t                              round_robin_owner;

  logic          [REQUESTER_COUNT-1:0] request_valids;
  logic                                arbitration_valid;
  owner_t                              arbitration_owner;
  logic                                arbitration_write;
  addr_t                               arbitration_address;
  logic          [     DATA_WIDTH-1:0] arbitration_write_data;
  fabric_strb_t                        arbitration_write_strobe;
  logic                                arbitration_last;

  logic                                request_write;
  addr_t                               request_address;
  logic          [     DATA_WIDTH-1:0] request_write_data;
  fabric_strb_t                        request_write_strobe;
  logic                                request_last;
  logic                                transaction_valid;
  logic                                transaction_aligned;
  logic                                transaction_is_spm;
  logic                                transaction_is_dram;
  logic                                transaction_is_legal;
  logic                                transaction_ready;
  logic                                request_fire;

  logic                                owner_response_ready;
  logic                                response_fire;
  logic          [     DATA_WIDTH-1:0] response_data;
  logic                                response_error;

  logic                                scratchpad_read_enable;
  logic                                scratchpad_read_valid;
  logic          [     DATA_WIDTH-1:0] scratchpad_read_data;
  logic                                scratchpad_read_error;
  logic                                scratchpad_write_enable;
  logic                                scratchpad_write_error;

  logic          [     DATA_WIDTH-1:0] local_response_data;
  logic                                local_response_error;

  initial begin : validate_parameters
    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % BITS_PER_BYTE) != 0)) begin
      $fatal(1, "Memory fabric data width must contain a positive whole number of bytes");
    end
    if (DATA_WIDTH != soc_pkg::DATA_WIDTH) begin
      $fatal(1, "Memory fabric currently requires the shared SoC data width");
    end
  end

  always_comb begin
    request_valids[OWNER_DMA_SOURCE] = dma_source_port.req_valid;
    request_valids[OWNER_DMA_DESTINATION] = dma_destination_port.req_valid;
    request_valids[OWNER_VECTOR] = vector_port.req_valid;
    request_valids[OWNER_REDUCTION] = reduction_port.req_valid;
    request_valids[OWNER_GEMM] = gemm_port.req_valid;

    arbitration_valid = 1'b0;
    arbitration_owner = round_robin_owner;
    for (int unsigned offset = 0; offset < REQUESTER_COUNT; offset++) begin
      if (!arbitration_valid &&
          request_valids[(int'(round_robin_owner)+offset)%REQUESTER_COUNT]) begin
        arbitration_valid = 1'b1;
        arbitration_owner = owner_t'((int'(round_robin_owner) + offset) % REQUESTER_COUNT);
      end
    end

    arbitration_write = 1'b0;
    arbitration_address = '0;
    arbitration_write_data = '0;
    arbitration_write_strobe = '0;
    arbitration_last = 1'b0;
    case (arbitration_owner)
      OWNER_DMA_SOURCE: begin
        arbitration_write = dma_source_port.req_write;
        arbitration_address = dma_source_port.req_addr;
        arbitration_write_data = dma_source_port.req_wdata;
        arbitration_write_strobe = dma_source_port.req_wstrb;
        arbitration_last = dma_source_port.req_last;
      end
      OWNER_DMA_DESTINATION: begin
        arbitration_write = dma_destination_port.req_write;
        arbitration_address = dma_destination_port.req_addr;
        arbitration_write_data = dma_destination_port.req_wdata;
        arbitration_write_strobe = dma_destination_port.req_wstrb;
        arbitration_last = dma_destination_port.req_last;
      end
      OWNER_VECTOR: begin
        arbitration_write = vector_port.req_write;
        arbitration_address = vector_port.req_addr;
        arbitration_write_data = vector_port.req_wdata;
        arbitration_write_strobe = vector_port.req_wstrb;
        arbitration_last = vector_port.req_last;
      end
      OWNER_REDUCTION: begin
        arbitration_write = reduction_port.req_write;
        arbitration_address = reduction_port.req_addr;
        arbitration_write_data = reduction_port.req_wdata;
        arbitration_write_strobe = reduction_port.req_wstrb;
        arbitration_last = reduction_port.req_last;
      end
      OWNER_GEMM: begin
        arbitration_write = gemm_port.req_write;
        arbitration_address = gemm_port.req_addr;
        arbitration_write_data = gemm_port.req_wdata;
        arbitration_write_strobe = gemm_port.req_wstrb;
        arbitration_last = gemm_port.req_last;
      end
      default: begin
      end
    endcase
  end

  always_comb begin
    transaction_valid = 1'b0;
    case (transaction_owner)
      OWNER_DMA_SOURCE: transaction_valid = dma_source_port.req_valid;
      OWNER_DMA_DESTINATION: transaction_valid = dma_destination_port.req_valid;
      OWNER_VECTOR: transaction_valid = vector_port.req_valid;
      OWNER_REDUCTION: transaction_valid = reduction_port.req_valid;
      OWNER_GEMM: transaction_valid = gemm_port.req_valid;
      default: transaction_valid = 1'b0;
    endcase
  end

  assign transaction_aligned = request_address[WORD_ADDRESS_LSB-1:0] == '0;
  assign transaction_is_spm = transaction_aligned && is_spm_address(
      request_address
  ) && data_range_is_legal(
      request_address, byte_count_t'(FABRIC_DATA_BYTES)
  );
  assign transaction_is_dram = transaction_aligned && is_dram_address(
      request_address
  ) && data_range_is_legal(
      request_address, byte_count_t'(FABRIC_DATA_BYTES)
  );
  assign transaction_is_legal = transaction_is_spm || transaction_is_dram;
  assign transaction_ready = transaction_is_dram ? external_port.req_ready : 1'b1;
  assign request_fire = (state == FABRIC_REQUEST) && transaction_valid && transaction_ready;

  assign dma_source_port.req_ready = (state == FABRIC_REQUEST) &&
      (transaction_owner == OWNER_DMA_SOURCE) && transaction_ready;
  assign dma_destination_port.req_ready = (state == FABRIC_REQUEST) &&
      (transaction_owner == OWNER_DMA_DESTINATION) && transaction_ready;
  assign vector_port.req_ready = (state == FABRIC_REQUEST) && (transaction_owner == OWNER_VECTOR) &&
      transaction_ready;
  assign reduction_port.req_ready = (state == FABRIC_REQUEST) &&
      (transaction_owner == OWNER_REDUCTION) && transaction_ready;
  assign gemm_port.req_ready = (state == FABRIC_REQUEST) && (transaction_owner == OWNER_GEMM) &&
      transaction_ready;

  assign external_port.req_valid = (state == FABRIC_REQUEST) && transaction_valid &&
      transaction_is_dram;
  assign external_port.req_write = request_write;
  assign external_port.req_addr = request_address;
  assign external_port.req_wdata = request_write_data;
  assign external_port.req_wstrb = request_write_strobe;
  assign external_port.req_last = request_last;

  assign scratchpad_read_enable = request_fire && transaction_is_spm && !request_write;
  assign scratchpad_write_enable = request_fire && transaction_is_spm && request_write;

  always_comb begin
    owner_response_ready = 1'b0;
    case (transaction_owner)
      OWNER_DMA_SOURCE: owner_response_ready = dma_source_port.rsp_ready;
      OWNER_DMA_DESTINATION: owner_response_ready = dma_destination_port.rsp_ready;
      OWNER_VECTOR: owner_response_ready = vector_port.rsp_ready;
      OWNER_REDUCTION: owner_response_ready = reduction_port.rsp_ready;
      OWNER_GEMM: owner_response_ready = gemm_port.rsp_ready;
      default: owner_response_ready = 1'b0;
    endcase
  end

  assign response_data = (state == FABRIC_EXTERNAL_RESPONSE) ? external_port.rsp_rdata :
      local_response_data;
  assign response_error = (state == FABRIC_EXTERNAL_RESPONSE) ? external_port.rsp_error :
      local_response_error;

  assign dma_source_port.rsp_valid =
      ((state == FABRIC_LOCAL_RESPONSE) ||
       ((state == FABRIC_EXTERNAL_RESPONSE) && external_port.rsp_valid)) &&
      (transaction_owner == OWNER_DMA_SOURCE);
  assign dma_source_port.rsp_rdata = response_data;
  assign dma_source_port.rsp_error = response_error;

  assign dma_destination_port.rsp_valid =
      ((state == FABRIC_LOCAL_RESPONSE) ||
       ((state == FABRIC_EXTERNAL_RESPONSE) && external_port.rsp_valid)) &&
      (transaction_owner == OWNER_DMA_DESTINATION);
  assign dma_destination_port.rsp_rdata = response_data;
  assign dma_destination_port.rsp_error = response_error;

  assign vector_port.rsp_valid = ((state == FABRIC_LOCAL_RESPONSE) ||
                                  ((state == FABRIC_EXTERNAL_RESPONSE) &&
                                   external_port.rsp_valid)) && (transaction_owner == OWNER_VECTOR);
  assign vector_port.rsp_rdata = response_data;
  assign vector_port.rsp_error = response_error;

  assign reduction_port.rsp_valid =
      ((state == FABRIC_LOCAL_RESPONSE) ||
       ((state == FABRIC_EXTERNAL_RESPONSE) && external_port.rsp_valid)) &&
      (transaction_owner == OWNER_REDUCTION);
  assign reduction_port.rsp_rdata = response_data;
  assign reduction_port.rsp_error = response_error;

  assign gemm_port.rsp_valid = ((state == FABRIC_LOCAL_RESPONSE) ||
                                ((state == FABRIC_EXTERNAL_RESPONSE) && external_port.rsp_valid)) &&
      (transaction_owner == OWNER_GEMM);
  assign gemm_port.rsp_rdata = response_data;
  assign gemm_port.rsp_error = response_error;

  assign external_port.rsp_ready = (state == FABRIC_EXTERNAL_RESPONSE) && owner_response_ready;
  assign response_fire = ((state == FABRIC_LOCAL_RESPONSE) && owner_response_ready) ||
      ((state == FABRIC_EXTERNAL_RESPONSE) && external_port.rsp_valid && owner_response_ready);
  assign busy = state != FABRIC_IDLE;

  scratchpad_ram #(
      .DATA_WIDTH(DATA_WIDTH)
  ) u_scratchpad (
      .clk     (clk),
      .rst_n   (rst_n),
      .rd_en   (scratchpad_read_enable),
      .rd_addr (request_address),
      .rd_valid(scratchpad_read_valid),
      .rd_data (scratchpad_read_data),
      .rd_error(scratchpad_read_error),
      .wr_en   (scratchpad_write_enable),
      .wr_addr (request_address),
      .wr_data (request_write_data),
      .wr_strb (request_write_strobe),
      .wr_error(scratchpad_write_error)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= FABRIC_IDLE;
      transaction_owner <= OWNER_DMA_SOURCE;
      round_robin_owner <= OWNER_DMA_SOURCE;
      request_write <= 1'b0;
      request_address <= '0;
      request_write_data <= '0;
      request_write_strobe <= '0;
      request_last <= 1'b0;
      local_response_data <= '0;
      local_response_error <= 1'b0;
      error_event <= 1'b0;
    end else begin
      error_event <= 1'b0;
      unique case (state)
        FABRIC_IDLE: begin
          if (arbitration_valid) begin
            transaction_owner <= arbitration_owner;
            request_write <= arbitration_write;
            request_address <= arbitration_address;
            request_write_data <= arbitration_write_data;
            request_write_strobe <= arbitration_write_strobe;
            request_last <= arbitration_last;
            state <= FABRIC_REQUEST;
          end
        end

        FABRIC_REQUEST: begin
          if (request_fire) begin
            if (transaction_owner == LAST_OWNER) begin
              round_robin_owner <= OWNER_DMA_SOURCE;
            end else begin
              round_robin_owner <= transaction_owner + 1'b1;
            end

            if (!transaction_is_legal) begin
              local_response_data <= '0;
              local_response_error <= 1'b1;
              error_event <= 1'b1;
              state <= FABRIC_LOCAL_RESPONSE;
            end else if (transaction_is_spm && request_write) begin
              local_response_data <= '0;
              local_response_error <= scratchpad_write_error;
              error_event <= scratchpad_write_error;
              state <= FABRIC_LOCAL_RESPONSE;
            end else if (transaction_is_spm) begin
              if (scratchpad_read_error) begin
                local_response_data <= '0;
                local_response_error <= 1'b1;
                error_event <= 1'b1;
                state <= FABRIC_LOCAL_RESPONSE;
              end else begin
                state <= FABRIC_SPM_READ_WAIT;
              end
            end else begin
              state <= FABRIC_EXTERNAL_RESPONSE;
            end
          end
        end

        FABRIC_SPM_READ_WAIT: begin
          if (scratchpad_read_valid) begin
            local_response_data <= scratchpad_read_data;
            local_response_error <= 1'b0;
            state <= FABRIC_LOCAL_RESPONSE;
          end
        end

        FABRIC_LOCAL_RESPONSE: begin
          if (response_fire) begin
            state <= FABRIC_IDLE;
          end
        end

        FABRIC_EXTERNAL_RESPONSE: begin
          if (response_fire) begin
            error_event <= external_port.rsp_error;
            state <= FABRIC_IDLE;
          end
        end

        default: begin
          state <= FABRIC_IDLE;
          error_event <= 1'b1;
        end
      endcase
    end
  end

  property p_request_ready_is_one_hot;
    @(posedge clk) disable iff (!rst_n) $onehot0(
        {
          dma_source_port.req_ready,
          dma_destination_port.req_ready,
          vector_port.req_ready,
          reduction_port.req_ready,
          gemm_port.req_ready
        }
    );
  endproperty

  property p_response_valid_is_one_hot;
    @(posedge clk) disable iff (!rst_n) $onehot0(
        {
          dma_source_port.rsp_valid,
          dma_destination_port.rsp_valid,
          vector_port.rsp_valid,
          reduction_port.rsp_valid,
          gemm_port.rsp_valid
        }
    );
  endproperty

  property p_granted_request_remains_stable;
    @(posedge clk) disable iff (!rst_n) state == FABRIC_REQUEST && !request_fire |=> $stable(
        {
          transaction_owner,
          request_write,
          request_address,
          request_write_data,
          request_write_strobe,
          request_last
        }
    );
  endproperty

  property p_external_request_is_legal;
    @(posedge clk) disable iff (!rst_n) external_port.req_valid |-> transaction_is_dram;
  endproperty

  property p_ready_requires_grant;
    @(posedge clk) disable iff (!rst_n) (
        dma_source_port.req_ready || dma_destination_port.req_ready || vector_port.req_ready ||
            reduction_port.req_ready || gemm_port.req_ready) |-> state == FABRIC_REQUEST;
  endproperty

  property p_state_is_legal;
    @(posedge clk) disable iff (!rst_n)
        state inside {FABRIC_IDLE, FABRIC_REQUEST, FABRIC_SPM_READ_WAIT, FABRIC_LOCAL_RESPONSE,
                      FABRIC_EXTERNAL_RESPONSE};
  endproperty

  a_request_ready_is_one_hot :
  assert property (p_request_ready_is_one_hot);
  a_response_valid_is_one_hot :
  assert property (p_response_valid_is_one_hot);
  a_granted_request_remains_stable :
  assert property (p_granted_request_remains_stable);
  a_external_request_is_legal :
  assert property (p_external_request_is_legal);
  a_ready_requires_grant :
  assert property (p_ready_requires_grant);
  a_state_is_legal :
  assert property (p_state_is_legal);

endmodule
