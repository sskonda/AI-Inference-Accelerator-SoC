class soc_coverage extends uvm_subscriber #(axil_item);
  `uvm_component_utils(soc_coverage)

  uvm_analysis_imp_mem_cov #(mem_item, soc_coverage) memory_export;
  uvm_analysis_imp_irq_cov #(irq_item, soc_coverage) irq_export;
  uvm_analysis_imp_cmd_cov #(cmd_item, soc_coverage) command_export;

  logic [AXIL_ADDR_WIDTH-1:0] register_address;
  bit register_write;
  command_opcode_e opcode;
  logic [PRIORITY_WIDTH-1:0] priority_level;
  int unsigned dma_length;
  int unsigned queue_occupancy;
  scheduler_policy_e scheduler_policy;
  error_e error_code;
  mem_direction_e memory_direction;
  int unsigned memory_latency;
  bit memory_error;
  bit irq_level;

  covergroup register_cg;
    option.per_instance = 1;
    address_cp: coverpoint register_address {
      bins identity[] = {reg_pkg::REG_SOC_ID, reg_pkg::REG_VERSION};
      bins control[] = {reg_pkg::REG_CTRL, reg_pkg::REG_STATUS, reg_pkg::REG_IRQ_STATUS,
                        reg_pkg::REG_IRQ_ENABLE, reg_pkg::REG_TIMER_CTRL, reg_pkg::REG_TIMER_VALUE};
      bins dma[] = {[reg_pkg::REG_DMA_SRC_ADDR : reg_pkg::REG_DMA_STATUS]};
      bins command[] = {[reg_pkg::REG_CMD_OPCODE : reg_pkg::REG_CMD_STATUS], reg_pkg::REG_CMD_ID,
                        reg_pkg::REG_SCHED_CTRL, reg_pkg::REG_QUEUE_STATUS};
      bins performance[] = {[reg_pkg::REG_PERF_SELECT : reg_pkg::REG_ERROR_STATUS]};
      bins illegal = default;
    }
    direction_cp: coverpoint register_write;
    address_direction_cross: cross address_cp, direction_cp;
  endgroup

  covergroup command_cg;
    option.per_instance = 1;
    opcode_cp: coverpoint opcode {
      bins legal[] = {CMD_OP_DMA_COPY, CMD_OP_VECTOR_ADD, CMD_OP_VECTOR_MULTIPLY,
                      CMD_OP_VECTOR_SCALE, CMD_OP_VECTOR_RELU, CMD_OP_VECTOR_CLAMP,
                      CMD_OP_REDUCE_SUM, CMD_OP_REDUCE_MAX, CMD_OP_GEMM};
      bins invalid = {CMD_OP_INVALID};
    }
    priority_cp: coverpoint priority_level;
    opcode_priority_cross: cross opcode_cp, priority_cp;
  endgroup

  covergroup dma_cg;
    option.per_instance = 1;
    length_cp: coverpoint dma_length {
      bins zero = {0};
      bins single_word = {[1 : DATA_BYTES]};
      bins short_transfer = {[DATA_BYTES + 1 : 32]};
      bins medium_transfer = {[33 : 256]};
      bins long_transfer = {[257 : $]};
    }
  endgroup

  covergroup scheduler_cg;
    option.per_instance = 1;
    occupancy_cp: coverpoint queue_occupancy {
      bins levels[] = {[0 : soc_pkg::DEFAULT_COMMAND_QUEUE_DEPTH]};
    }
    policy_cp: coverpoint scheduler_policy;
    policy_occupancy_cross: cross occupancy_cp, policy_cp;
  endgroup

  covergroup error_cg;
    option.per_instance = 1;
    code_cp: coverpoint error_code;
  endgroup

  covergroup memory_cg;
    option.per_instance = 1;
    direction_cp: coverpoint memory_direction;
    latency_cp: coverpoint memory_latency {
      bins immediate = {0}; bins short_delay = {[1 : 3]}; bins long_delay = {[4 : $]};
    }
    error_cp: coverpoint memory_error;
    direction_error_cross: cross direction_cp, error_cp;
  endgroup

  covergroup irq_cg;
    option.per_instance = 1;
    level_cp: coverpoint irq_level;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    memory_export = new("memory_export", this);
    irq_export = new("irq_export", this);
    command_export = new("command_export", this);
    register_cg = new();
    command_cg = new();
    dma_cg = new();
    scheduler_cg = new();
    error_cg = new();
    memory_cg = new();
    irq_cg = new();
  endfunction

  function void write(axil_item item);
    register_address = item.address;
    register_write   = item.direction == axil_item::AXIL_WRITE;
    register_cg.sample();

    if (item.direction == axil_item::AXIL_WRITE && item.response == AXIL_RESP_OKAY) begin
      case (item.address)
        reg_pkg::REG_CMD_OPCODE:   opcode = command_opcode_e'(item.write_data[OPCODE_WIDTH-1:0]);
        reg_pkg::REG_CMD_PRIORITY: priority_level = item.write_data[PRIORITY_WIDTH-1:0];
        reg_pkg::REG_CMD_SUBMIT:   command_cg.sample();
        reg_pkg::REG_DMA_LEN_BYTES: begin
          dma_length = item.write_data;
          dma_cg.sample();
        end
        reg_pkg::REG_SCHED_CTRL: begin
          scheduler_policy = item.write_data[reg_pkg::SCHED_POLICY_BIT] ? SCHED_PRIORITY_FIRST :
              SCHED_ROUND_ROBIN;
          scheduler_cg.sample();
        end
        default: begin
        end
      endcase
    end

    if (item.direction == axil_item::AXIL_READ && item.response == AXIL_RESP_OKAY) begin
      if (item.address == reg_pkg::REG_QUEUE_STATUS) begin
        queue_occupancy =
            item.read_data[reg_pkg::QUEUE_OCCUPANCY_LSB+:reg_pkg::QUEUE_OCCUPANCY_WIDTH];
        scheduler_cg.sample();
      end
      if (item.address == reg_pkg::REG_ERROR_STATUS) begin
        for (int unsigned index = 0; index < ERROR_STATUS_WIDTH; index++) begin
          if (item.read_data[index]) begin
            error_code = error_e'(index);
            error_cg.sample();
          end
        end
      end
    end
  endfunction

  function void write_mem_cov(mem_item item);
    memory_direction = item.direction;
    memory_latency = int'(item.response_cycle - item.request_cycle);
    memory_error = item.error;
    memory_cg.sample();
  endfunction

  function void write_irq_cov(irq_item item);
    irq_level = item.asserted;
    irq_cg.sample();
  endfunction

  function void write_cmd_cov(cmd_item item);
    opcode = item.opcode;
    queue_occupancy = item.queue_occupancy;
    command_cg.sample();
    scheduler_cg.sample();
  endfunction
endclass
