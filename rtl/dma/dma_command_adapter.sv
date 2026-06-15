module dma_command_adapter (
  input logic clk,
  input logic rst_n,

  input  logic                         command_valid,
  output logic                         command_ready,
  input  accel_pkg::command_desc_t     command,
  output logic                         response_valid,
  input  logic                         response_ready,
  output accel_pkg::command_response_t response,

  input logic                 mmio_start,
  input soc_pkg::addr_t       mmio_source_address,
  input soc_pkg::addr_t       mmio_destination_address,
  input soc_pkg::byte_count_t mmio_length_bytes,

  output logic                 engine_start,
  output soc_pkg::addr_t       engine_source_address,
  output soc_pkg::addr_t       engine_destination_address,
  output soc_pkg::byte_count_t engine_length_bytes,
  input  logic                 engine_busy,
  input  logic                 engine_done,
  input  logic                 engine_error,
  input  soc_pkg::error_e      engine_error_code
);

  import accel_pkg::*;
  import soc_pkg::*;

  typedef enum logic [1:0] {
    ADAPTER_IDLE,
    ADAPTER_WAIT,
    ADAPTER_RESPONSE
  } adapter_state_e;

  localparam data_t MAXIMUM_CYCLE_COUNT = '1;

  adapter_state_e                           state;
  command_response_t                        response_reg;
  logic              [COMMAND_ID_WIDTH-1:0] active_command_id;
  logic              [    LENGTH_WIDTH-1:0] active_length;
  data_t                                    active_cycles;
  logic                                     command_fire;

  assign command_ready = rst_n && (state == ADAPTER_IDLE) && !engine_busy && !mmio_start;
  assign command_fire = command_valid && command_ready;
  assign response_valid = state == ADAPTER_RESPONSE;
  assign response = response_reg;

  always_comb begin
    engine_start = mmio_start || command_fire;
    engine_source_address = mmio_source_address;
    engine_destination_address = mmio_destination_address;
    engine_length_bytes = mmio_length_bytes;
    if (command_fire) begin
      engine_source_address = command.src0_addr;
      engine_destination_address = command.dst_addr;
      engine_length_bytes = byte_count_t'(command.length);
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= ADAPTER_IDLE;
      response_reg <= '0;
      active_command_id <= '0;
      active_length <= '0;
      active_cycles <= '0;
    end else begin
      unique case (state)
        ADAPTER_IDLE: begin
          active_cycles <= '0;
          if (command_fire) begin
            active_command_id <= command.command_id;
            active_length <= command.length;
            state <= ADAPTER_WAIT;
          end
        end

        ADAPTER_WAIT: begin
          if (active_cycles != MAXIMUM_CYCLE_COUNT) begin
            active_cycles <= active_cycles + 1'b1;
          end
          if (engine_done) begin
            response_reg.command_id <= active_command_id;
            response_reg.opcode <= CMD_OP_DMA_COPY;
            response_reg.error <= engine_error ? engine_error_code : ERR_NONE;
            response_reg.result <= engine_error ? '0 : DATA_WIDTH'(active_length);
            response_reg.cycles <= (active_cycles == MAXIMUM_CYCLE_COUNT) ? MAXIMUM_CYCLE_COUNT :
                active_cycles + 1'b1;
            state <= ADAPTER_RESPONSE;
          end
        end

        ADAPTER_RESPONSE: begin
          if (response_valid && response_ready) begin
            state <= ADAPTER_IDLE;
          end
        end

        default: state <= ADAPTER_IDLE;
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

  property p_command_start_is_exclusive;
    @(posedge clk) disable iff (!rst_n) command_fire |-> !mmio_start && !engine_busy;
  endproperty

  property p_response_follows_engine_done;
    @(posedge clk) disable iff (!rst_n) response_valid && !$past(
        response_valid
    ) |-> $past(
        engine_done
    );
  endproperty

  property p_state_is_legal;
    @(posedge clk) disable iff (!rst_n) state inside {ADAPTER_IDLE, ADAPTER_WAIT, ADAPTER_RESPONSE};
  endproperty

  a_command_stable_while_stalled :
  assert property (p_command_stable_while_stalled);
  a_response_stable_while_stalled :
  assert property (p_response_stable_while_stalled);
  a_command_start_is_exclusive :
  assert property (p_command_start_is_exclusive);
  a_response_follows_engine_done :
  assert property (p_response_follows_engine_done);
  a_state_is_legal :
  assert property (p_state_is_legal);

endmodule
