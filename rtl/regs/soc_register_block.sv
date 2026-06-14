module soc_register_block (
  input logic               clk,
  input logic               rst_n,
        axil_if.subordinate axil,
        cmd_if.producer     command_port,

  input  logic                                           soc_busy,
  output logic                                           global_enable,
  output logic                                           perf_clear,
  output logic                                           scheduler_priority_mode,
  output logic [accel_pkg::STARVATION_COUNTER_WIDTH-1:0] scheduler_starvation_threshold,

  input  logic [soc_pkg::IRQ_SOURCE_COUNT-1:0] irq_pending,
  output logic [soc_pkg::IRQ_SOURCE_COUNT-1:0] irq_enable,
  output logic [soc_pkg::IRQ_SOURCE_COUNT-1:0] irq_clear,

  input  logic [          soc_pkg::DATA_WIDTH-1:0] timer_value,
  output logic                                     timer_enable,
  output logic                                     timer_periodic,
  output logic [reg_pkg::TIMER_INTERVAL_WIDTH-1:0] timer_interval,

  input  logic                 dma_busy,
  input  logic                 dma_done,
  input  logic                 dma_error,
  output logic                 dma_start,
  output logic                 dma_irq_enable,
  output soc_pkg::addr_t       dma_src_addr,
  output soc_pkg::addr_t       dma_dst_addr,
  output soc_pkg::byte_count_t dma_length_bytes,

  input logic                                       queue_full,
  input logic                                       queue_empty,
  input logic [ reg_pkg::QUEUE_OCCUPANCY_WIDTH-1:0] queue_occupancy,
  input logic [reg_pkg::QUEUE_HIGH_WATER_WIDTH-1:0] queue_high_water,

  output soc_pkg::perf_counter_id_e                                   perf_select,
  input  logic                      [soc_pkg::PERF_COUNTER_WIDTH-1:0] perf_value,

  input  logic [soc_pkg::ERROR_STATUS_WIDTH-1:0] hardware_error_set,
  output logic [soc_pkg::ERROR_STATUS_WIDTH-1:0] error_status
);

  import accel_pkg::*;
  import reg_pkg::*;
  import soc_pkg::*;

  localparam int unsigned ERROR_INDEX_WIDTH = width_for_index(ERROR_STATUS_WIDTH);

  logic                         aw_pending;
  reg_offset_t                  awaddr_reg;
  logic                         w_pending;
  data_t                        wdata_reg;
  strb_t                        wstrb_reg;

  data_t                        ctrl_reg;
  data_t                        irq_enable_reg;
  data_t                        timer_ctrl_reg;
  data_t                        dma_src_addr_reg;
  data_t                        dma_dst_addr_reg;
  data_t                        dma_length_reg;
  data_t                        dma_ctrl_reg;
  data_t                        cmd_opcode_reg;
  data_t                        cmd_src0_addr_reg;
  data_t                        cmd_src1_addr_reg;
  data_t                        cmd_dst_addr_reg;
  data_t                        cmd_length_reg;
  data_t                        cmd_m_reg;
  data_t                        cmd_n_reg;
  data_t                        cmd_k_reg;
  data_t                        cmd_flags_reg;
  data_t                        cmd_priority_reg;
  data_t                        cmd_id_reg;
  data_t                        perf_select_reg;
  data_t                        scheduler_ctrl_reg;

  logic                         dma_done_sticky;
  logic                         dma_error_sticky;
  logic                         cmd_done_sticky;
  logic                         cmd_error_sticky;
  logic        [DATA_WIDTH-1:0] perf_snapshot_high;

  logic                         write_execute;
  logic                         write_side_effect_enable;
  axil_resp_e                   write_response;
  error_e                       write_error;
  logic                         read_execute;
  axil_resp_e                   read_response;
  data_t                        read_data;
  error_e                       read_error;
  data_t                        error_set_mask;
  data_t                        error_clear_mask;
  data_t                        write_byte_mask;
  data_t                        write_active_data;

  function automatic data_t expand_strobe(input strb_t strobe);
    data_t mask;

    mask = '0;
    for (int unsigned byte_index = 0; byte_index < STRB_WIDTH; byte_index++) begin
      mask[byte_index*BITS_PER_BYTE+:BITS_PER_BYTE] = {BITS_PER_BYTE{strobe[byte_index]}};
    end
    return mask;
  endfunction

  function automatic data_t merge_by_strobe(input data_t old_value, input data_t new_value,
                                            input strb_t strobe);
    data_t mask;

    mask = expand_strobe(strobe);
    return (old_value & ~mask) | (new_value & mask);
  endfunction

  function automatic data_t error_code_mask(input error_e error_code);
    data_t mask;

    mask = '0;
    if (error_code != ERR_NONE) begin
      mask[ERROR_INDEX_WIDTH'(error_code)] = 1'b1;
    end
    return mask;
  endfunction

  function automatic data_t read_register(input reg_offset_t offset);
    data_t value;

    value = '0;
    case (offset)
      REG_SOC_ID: value = SOC_ID_VALUE;
      REG_VERSION: value = VERSION_VALUE;
      REG_CTRL: value = ctrl_reg;
      REG_STATUS: begin
        value[STATUS_READY_BIT] = rst_n;
        value[STATUS_BUSY_BIT]  = soc_busy;
        value[STATUS_ERROR_BIT] = |error_status;
      end
      REG_IRQ_STATUS: value[IRQ_SOURCE_COUNT-1:0] = irq_pending;
      REG_IRQ_ENABLE: value[IRQ_SOURCE_COUNT-1:0] = irq_enable_reg[IRQ_SOURCE_COUNT-1:0];
      REG_TIMER_CTRL: value = timer_ctrl_reg;
      REG_TIMER_VALUE: value = timer_value;
      REG_DMA_SRC_ADDR: value = dma_src_addr_reg;
      REG_DMA_DST_ADDR: value = dma_dst_addr_reg;
      REG_DMA_LEN_BYTES: value = dma_length_reg;
      REG_DMA_CTRL: value = dma_ctrl_reg;
      REG_DMA_STATUS: begin
        value[DMA_STATUS_BUSY_BIT]  = dma_busy;
        value[DMA_STATUS_DONE_BIT]  = dma_done_sticky;
        value[DMA_STATUS_ERROR_BIT] = dma_error_sticky;
      end
      REG_CMD_OPCODE: value = cmd_opcode_reg;
      REG_CMD_SRC0_ADDR: value = cmd_src0_addr_reg;
      REG_CMD_SRC1_ADDR: value = cmd_src1_addr_reg;
      REG_CMD_DST_ADDR: value = cmd_dst_addr_reg;
      REG_CMD_LEN: value = cmd_length_reg;
      REG_CMD_M: value = cmd_m_reg;
      REG_CMD_N: value = cmd_n_reg;
      REG_CMD_K: value = cmd_k_reg;
      REG_CMD_FLAGS: value = cmd_flags_reg;
      REG_CMD_PRIORITY: value = cmd_priority_reg;
      REG_CMD_STATUS: begin
        value[CMD_STATUS_DONE_BIT] = cmd_done_sticky;
        value[CMD_STATUS_ERROR_BIT] = cmd_error_sticky;
        value[CMD_STATUS_FULL_BIT] = queue_full;
        value[CMD_STATUS_EMPTY_BIT] = queue_empty;
        value[CMD_STATUS_PENDING_BIT] = command_port.cmd_valid;
      end
      REG_PERF_SELECT: value = perf_select_reg;
      REG_PERF_VALUE: value = perf_value[DATA_WIDTH-1:0];
      REG_PERF_VALUE_HI: value = perf_snapshot_high;
      REG_ERROR_STATUS: value = error_status;
      REG_CMD_ID: value = cmd_id_reg;
      REG_SCHED_CTRL: value = scheduler_ctrl_reg;
      REG_QUEUE_STATUS: begin
        value[QUEUE_OCCUPANCY_LSB+:QUEUE_OCCUPANCY_WIDTH] = queue_occupancy;
        value[QUEUE_HIGH_WATER_LSB+:QUEUE_HIGH_WATER_WIDTH] = queue_high_water;
        value[QUEUE_FULL_BIT] = queue_full;
        value[QUEUE_EMPTY_BIT] = queue_empty;
      end
      default: value = '0;
    endcase
    return value;
  endfunction

  always_comb begin
    axil.awready = rst_n && !aw_pending && !axil.bvalid;
    axil.wready = rst_n && !w_pending && !axil.bvalid;
    axil.arready = rst_n && !axil.rvalid;

    write_execute = aw_pending && w_pending && !axil.bvalid;
    write_byte_mask = expand_strobe(wstrb_reg);
    write_active_data = wdata_reg & write_byte_mask;
    write_response = AXIL_RESP_OKAY;
    write_error = ERR_NONE;

    if (!is_legal_offset(awaddr_reg)) begin
      write_response = AXIL_RESP_SLVERR;
      write_error = ERR_ILLEGAL_MMIO;
    end else if (is_read_only_offset(awaddr_reg)) begin
      write_response = AXIL_RESP_SLVERR;
      write_error = ERR_READ_ONLY;
    end else
        if ((awaddr_reg == REG_DMA_CTRL) && write_active_data[DMA_CTRL_START_BIT] && dma_busy) begin
      write_response = AXIL_RESP_SLVERR;
      write_error = ERR_DMA_BUSY;
    end else if ((awaddr_reg == REG_CMD_SUBMIT) && write_active_data[CMD_SUBMIT_BIT] &&
                 command_port.cmd_valid) begin
      write_response = AXIL_RESP_SLVERR;
      write_error = ERR_QUEUE_FULL;
    end else if ((awaddr_reg == REG_CMD_SUBMIT) && write_active_data[CMD_SUBMIT_BIT] &&
                 (queue_full || command_port.cmd_full)) begin
      write_response = AXIL_RESP_SLVERR;
      write_error = ERR_QUEUE_FULL;
    end else
        if ((awaddr_reg == REG_CMD_SUBMIT) && write_active_data[CMD_SUBMIT_BIT] && !is_valid_opcode(
            command_opcode_e'(cmd_opcode_reg[OPCODE_WIDTH-1:0])
        )) begin
      write_response = AXIL_RESP_SLVERR;
      write_error = ERR_OPCODE;
    end

    write_side_effect_enable = write_execute && (write_response == AXIL_RESP_OKAY);

    read_execute = axil.arvalid && axil.arready;
    read_response = AXIL_RESP_OKAY;
    read_error = ERR_NONE;
    read_data = read_register(reg_offset_t'(axil.araddr));
    if (!is_legal_offset(
            reg_offset_t'(axil.araddr)
        ) || is_write_only_offset(
            reg_offset_t'(axil.araddr)
        )) begin
      read_response = AXIL_RESP_SLVERR;
      read_error = ERR_ILLEGAL_MMIO;
      read_data = '0;
    end

    error_set_mask = hardware_error_set;
    if (write_execute && (write_error != ERR_NONE)) begin
      error_set_mask |= error_code_mask(write_error);
    end
    if (read_execute && (read_error != ERR_NONE)) begin
      error_set_mask |= error_code_mask(read_error);
    end
    if (dma_error) begin
      error_set_mask |= error_code_mask(ERR_INTERNAL);
    end
    if (command_port.rsp_valid && rst_n && (command_port.rsp.error != ERR_NONE)) begin
      error_set_mask |= error_code_mask(command_port.rsp.error);
    end

    error_clear_mask = '0;
    if (write_side_effect_enable && (awaddr_reg == REG_ERROR_STATUS)) begin
      error_clear_mask = write_active_data;
    end

    global_enable = ctrl_reg[CTRL_ENABLE_BIT];
    scheduler_priority_mode = scheduler_ctrl_reg[SCHED_POLICY_BIT];
    scheduler_starvation_threshold =
        scheduler_ctrl_reg[SCHED_STARVATION_LSB+:SCHED_STARVATION_WIDTH];
    irq_enable = irq_enable_reg[IRQ_SOURCE_COUNT-1:0];
    timer_enable = timer_ctrl_reg[TIMER_ENABLE_BIT];
    timer_periodic = timer_ctrl_reg[TIMER_PERIODIC_BIT];
    timer_interval = timer_ctrl_reg[TIMER_INTERVAL_LSB+:TIMER_INTERVAL_WIDTH];
    dma_irq_enable = dma_ctrl_reg[DMA_CTRL_IRQ_ENABLE_BIT];
    dma_src_addr = addr_t'(dma_src_addr_reg);
    dma_dst_addr = addr_t'(dma_dst_addr_reg);
    dma_length_bytes = byte_count_t'(dma_length_reg);
    perf_select = perf_counter_id_e'(perf_select_reg[PERF_COUNTER_ID_WIDTH-1:0]);

    command_port.cmd.opcode = command_opcode_e'(cmd_opcode_reg[OPCODE_WIDTH-1:0]);
    command_port.cmd.src0_addr = addr_t'(cmd_src0_addr_reg);
    command_port.cmd.src1_addr = addr_t'(cmd_src1_addr_reg);
    command_port.cmd.dst_addr = addr_t'(cmd_dst_addr_reg);
    command_port.cmd.length = cmd_length_reg[LENGTH_WIDTH-1:0];
    command_port.cmd.m = cmd_m_reg[DIMENSION_WIDTH-1:0];
    command_port.cmd.n = cmd_n_reg[DIMENSION_WIDTH-1:0];
    command_port.cmd.k = cmd_k_reg[DIMENSION_WIDTH-1:0];
    command_port.cmd.flags = cmd_flags_reg[FLAGS_WIDTH-1:0];
    command_port.cmd.priority_level = cmd_priority_reg[PRIORITY_WIDTH-1:0];
    command_port.cmd.command_id = cmd_id_reg[COMMAND_ID_WIDTH-1:0];
  end

  assign command_port.rsp_ready = rst_n;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      aw_pending <= 1'b0;
      awaddr_reg <= '0;
      w_pending  <= 1'b0;
      wdata_reg  <= '0;
      wstrb_reg  <= '0;
    end else begin
      if (axil.awvalid && axil.awready) begin
        aw_pending <= 1'b1;
        awaddr_reg <= reg_offset_t'(axil.awaddr);
      end
      if (axil.wvalid && axil.wready) begin
        w_pending <= 1'b1;
        wdata_reg <= axil.wdata;
        wstrb_reg <= axil.wstrb;
      end
      if (write_execute) begin
        aw_pending <= 1'b0;
        w_pending  <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      axil.bvalid <= 1'b0;
      axil.bresp  <= AXIL_RESP_OKAY;
    end else begin
      if (axil.bvalid && axil.bready) begin
        axil.bvalid <= 1'b0;
      end
      if (write_execute) begin
        axil.bvalid <= 1'b1;
        axil.bresp  <= write_response;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      axil.rvalid <= 1'b0;
      axil.rdata  <= '0;
      axil.rresp  <= AXIL_RESP_OKAY;
    end else begin
      if (axil.rvalid && axil.rready) begin
        axil.rvalid <= 1'b0;
      end
      if (read_execute) begin
        axil.rvalid <= 1'b1;
        axil.rdata  <= read_data;
        axil.rresp  <= read_response;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ctrl_reg <= '0;
      irq_enable_reg <= '0;
      timer_ctrl_reg <= '0;
      dma_src_addr_reg <= '0;
      dma_dst_addr_reg <= '0;
      dma_length_reg <= '0;
      dma_ctrl_reg <= '0;
      cmd_opcode_reg <= '0;
      cmd_src0_addr_reg <= '0;
      cmd_src1_addr_reg <= '0;
      cmd_dst_addr_reg <= '0;
      cmd_length_reg <= '0;
      cmd_m_reg <= '0;
      cmd_n_reg <= '0;
      cmd_k_reg <= '0;
      cmd_flags_reg <= '0;
      cmd_priority_reg <= '0;
      cmd_id_reg <= '0;
      perf_select_reg <= '0;
      scheduler_ctrl_reg <= '0;
      perf_clear <= 1'b0;
      dma_start <= 1'b0;
      irq_clear <= '0;
    end else begin
      perf_clear <= 1'b0;
      dma_start  <= 1'b0;
      irq_clear  <= '0;

      if (write_side_effect_enable) begin
        case (awaddr_reg)
          REG_CTRL: begin
            ctrl_reg <= merge_by_strobe(
                ctrl_reg, wdata_reg, wstrb_reg
            ) & ~(data_t'(1) << CTRL_PERF_CLEAR_BIT);
            perf_clear <= write_active_data[CTRL_PERF_CLEAR_BIT];
            if (write_byte_mask[CTRL_PRIORITY_POLICY_BIT]) begin
              scheduler_ctrl_reg[SCHED_POLICY_BIT] <= wdata_reg[CTRL_PRIORITY_POLICY_BIT];
            end
          end
          REG_IRQ_STATUS: irq_clear <= write_active_data[IRQ_SOURCE_COUNT-1:0];
          REG_IRQ_ENABLE: irq_enable_reg <= merge_by_strobe(irq_enable_reg, wdata_reg, wstrb_reg);
          REG_TIMER_CTRL: timer_ctrl_reg <= merge_by_strobe(timer_ctrl_reg, wdata_reg, wstrb_reg);
          REG_DMA_SRC_ADDR:
          dma_src_addr_reg <= merge_by_strobe(dma_src_addr_reg, wdata_reg, wstrb_reg);
          REG_DMA_DST_ADDR:
          dma_dst_addr_reg <= merge_by_strobe(dma_dst_addr_reg, wdata_reg, wstrb_reg);
          REG_DMA_LEN_BYTES:
          dma_length_reg <= merge_by_strobe(dma_length_reg, wdata_reg, wstrb_reg);
          REG_DMA_CTRL: begin
            dma_ctrl_reg <= merge_by_strobe(
                dma_ctrl_reg, wdata_reg, wstrb_reg
            ) & ~(data_t'(1) << DMA_CTRL_START_BIT);
            dma_start <= write_active_data[DMA_CTRL_START_BIT];
          end
          REG_CMD_OPCODE: cmd_opcode_reg <= merge_by_strobe(cmd_opcode_reg, wdata_reg, wstrb_reg);
          REG_CMD_SRC0_ADDR:
          cmd_src0_addr_reg <= merge_by_strobe(cmd_src0_addr_reg, wdata_reg, wstrb_reg);
          REG_CMD_SRC1_ADDR:
          cmd_src1_addr_reg <= merge_by_strobe(cmd_src1_addr_reg, wdata_reg, wstrb_reg);
          REG_CMD_DST_ADDR:
          cmd_dst_addr_reg <= merge_by_strobe(cmd_dst_addr_reg, wdata_reg, wstrb_reg);
          REG_CMD_LEN: cmd_length_reg <= merge_by_strobe(cmd_length_reg, wdata_reg, wstrb_reg);
          REG_CMD_M: cmd_m_reg <= merge_by_strobe(cmd_m_reg, wdata_reg, wstrb_reg);
          REG_CMD_N: cmd_n_reg <= merge_by_strobe(cmd_n_reg, wdata_reg, wstrb_reg);
          REG_CMD_K: cmd_k_reg <= merge_by_strobe(cmd_k_reg, wdata_reg, wstrb_reg);
          REG_CMD_FLAGS: cmd_flags_reg <= merge_by_strobe(cmd_flags_reg, wdata_reg, wstrb_reg);
          REG_CMD_PRIORITY:
          cmd_priority_reg <= merge_by_strobe(cmd_priority_reg, wdata_reg, wstrb_reg);
          REG_PERF_SELECT:
          perf_select_reg <= merge_by_strobe(perf_select_reg, wdata_reg, wstrb_reg);
          REG_CMD_ID: cmd_id_reg <= merge_by_strobe(cmd_id_reg, wdata_reg, wstrb_reg);
          REG_SCHED_CTRL: begin
            scheduler_ctrl_reg <= merge_by_strobe(scheduler_ctrl_reg, wdata_reg, wstrb_reg);
            if (write_byte_mask[SCHED_POLICY_BIT]) begin
              ctrl_reg[CTRL_PRIORITY_POLICY_BIT] <= wdata_reg[SCHED_POLICY_BIT];
            end
          end
          default: begin
          end
        endcase
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      error_status <= '0;
    end else begin
      error_status <= (error_status & ~error_clear_mask) | error_set_mask;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      dma_done_sticky  <= 1'b0;
      dma_error_sticky <= 1'b0;
    end else begin
      if (write_side_effect_enable && (awaddr_reg == REG_DMA_STATUS)) begin
        if (write_active_data[DMA_STATUS_DONE_BIT]) begin
          dma_done_sticky <= 1'b0;
        end
        if (write_active_data[DMA_STATUS_ERROR_BIT]) begin
          dma_error_sticky <= 1'b0;
        end
      end
      if (dma_done) begin
        dma_done_sticky <= 1'b1;
      end
      if (dma_error) begin
        dma_error_sticky <= 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cmd_done_sticky  <= 1'b0;
      cmd_error_sticky <= 1'b0;
    end else begin
      if (write_side_effect_enable && (awaddr_reg == REG_CMD_STATUS)) begin
        if (write_active_data[CMD_STATUS_DONE_BIT]) begin
          cmd_done_sticky <= 1'b0;
        end
        if (write_active_data[CMD_STATUS_ERROR_BIT]) begin
          cmd_error_sticky <= 1'b0;
        end
      end
      if (command_port.rsp_valid && command_port.rsp_ready) begin
        cmd_done_sticky <= 1'b1;
        if (command_port.rsp.error != ERR_NONE) begin
          cmd_error_sticky <= 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      command_port.cmd_valid <= 1'b0;
    end else begin
      if (command_port.cmd_valid && command_port.cmd_ready) begin
        command_port.cmd_valid <= 1'b0;
      end
      if (write_side_effect_enable && (awaddr_reg == REG_CMD_SUBMIT) &&
          write_active_data[CMD_SUBMIT_BIT]) begin
        command_port.cmd_valid <= 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      perf_snapshot_high <= '0;
    end else if (read_execute && (reg_offset_t'(axil.araddr) == REG_PERF_VALUE)) begin
      perf_snapshot_high <= perf_value[PERF_COUNTER_WIDTH-1:DATA_WIDTH];
    end
  end

  property p_no_illegal_write_side_effect;
    @(posedge clk) disable iff (!rst_n) write_execute &&
        (write_response != AXIL_RESP_OKAY) |-> !write_side_effect_enable;
  endproperty

  property p_dma_start_self_clears;
    @(posedge clk) disable iff (!rst_n) dma_start |=> !dma_start;
  endproperty

  property p_perf_clear_self_clears;
    @(posedge clk) disable iff (!rst_n) perf_clear |=> !perf_clear;
  endproperty

  property p_known_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {
          aw_pending,
          w_pending,
          axil.bvalid,
          axil.rvalid,
          dma_start,
          perf_clear,
          command_port.cmd_valid
        }
    );
  endproperty

  a_no_illegal_write_side_effect :
  assert property (p_no_illegal_write_side_effect);
  a_dma_start_self_clears :
  assert property (p_dma_start_self_clears);
  a_perf_clear_self_clears :
  assert property (p_perf_clear_self_clears);
  a_known_control :
  assert property (p_known_control);

endmodule
