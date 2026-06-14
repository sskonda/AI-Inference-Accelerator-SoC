package reg_pkg;

  import soc_pkg::*;

  typedef logic [AXIL_ADDR_WIDTH-1:0] reg_offset_t;

  localparam logic [DATA_WIDTH-1:0] SOC_ID_VALUE = 32'h534f_4301;
  localparam logic [DATA_WIDTH-1:0] VERSION_VALUE = 32'h0001_0000;

  localparam reg_offset_t REG_SOC_ID = 12'h000;
  localparam reg_offset_t REG_VERSION = 12'h004;
  localparam reg_offset_t REG_CTRL = 12'h008;
  localparam reg_offset_t REG_STATUS = 12'h00c;
  localparam reg_offset_t REG_IRQ_STATUS = 12'h010;
  localparam reg_offset_t REG_IRQ_ENABLE = 12'h014;
  localparam reg_offset_t REG_TIMER_CTRL = 12'h018;
  localparam reg_offset_t REG_TIMER_VALUE = 12'h01c;
  localparam reg_offset_t REG_DMA_SRC_ADDR = 12'h020;
  localparam reg_offset_t REG_DMA_DST_ADDR = 12'h024;
  localparam reg_offset_t REG_DMA_LEN_BYTES = 12'h028;
  localparam reg_offset_t REG_DMA_CTRL = 12'h02c;
  localparam reg_offset_t REG_DMA_STATUS = 12'h030;
  localparam reg_offset_t REG_CMD_OPCODE = 12'h034;
  localparam reg_offset_t REG_CMD_SRC0_ADDR = 12'h038;
  localparam reg_offset_t REG_CMD_SRC1_ADDR = 12'h03c;
  localparam reg_offset_t REG_CMD_DST_ADDR = 12'h040;
  localparam reg_offset_t REG_CMD_LEN = 12'h044;
  localparam reg_offset_t REG_CMD_M = 12'h048;
  localparam reg_offset_t REG_CMD_N = 12'h04c;
  localparam reg_offset_t REG_CMD_K = 12'h050;
  localparam reg_offset_t REG_CMD_FLAGS = 12'h054;
  localparam reg_offset_t REG_CMD_PRIORITY = 12'h058;
  localparam reg_offset_t REG_CMD_SUBMIT = 12'h05c;
  localparam reg_offset_t REG_CMD_STATUS = 12'h060;
  localparam reg_offset_t REG_PERF_SELECT = 12'h064;
  localparam reg_offset_t REG_PERF_VALUE = 12'h068;
  localparam reg_offset_t REG_PERF_VALUE_HI = 12'h06c;
  localparam reg_offset_t REG_ERROR_STATUS = 12'h070;
  localparam reg_offset_t REG_CMD_ID = 12'h074;
  localparam reg_offset_t REG_SCHED_CTRL = 12'h078;
  localparam reg_offset_t REG_QUEUE_STATUS = 12'h07c;

  localparam int unsigned CTRL_ENABLE_BIT = 0;
  localparam int unsigned CTRL_PERF_CLEAR_BIT = 1;
  localparam int unsigned CTRL_PRIORITY_POLICY_BIT = 2;

  localparam int unsigned STATUS_READY_BIT = 0;
  localparam int unsigned STATUS_BUSY_BIT = 1;
  localparam int unsigned STATUS_ERROR_BIT = 2;

  localparam int unsigned TIMER_ENABLE_BIT = 0;
  localparam int unsigned TIMER_PERIODIC_BIT = 1;
  localparam int unsigned TIMER_INTERVAL_LSB = 8;
  localparam int unsigned TIMER_INTERVAL_WIDTH = 24;

  localparam int unsigned DMA_CTRL_START_BIT = 0;
  localparam int unsigned DMA_CTRL_IRQ_ENABLE_BIT = 1;
  localparam int unsigned DMA_STATUS_BUSY_BIT = 0;
  localparam int unsigned DMA_STATUS_DONE_BIT = 1;
  localparam int unsigned DMA_STATUS_ERROR_BIT = 2;

  localparam int unsigned CMD_SUBMIT_BIT = 0;
  localparam int unsigned CMD_STATUS_DONE_BIT = 0;
  localparam int unsigned CMD_STATUS_ERROR_BIT = 1;
  localparam int unsigned CMD_STATUS_FULL_BIT = 2;
  localparam int unsigned CMD_STATUS_EMPTY_BIT = 3;
  localparam int unsigned CMD_STATUS_PENDING_BIT = 4;

  localparam int unsigned SCHED_POLICY_BIT = 0;
  localparam int unsigned SCHED_STARVATION_LSB = 8;
  localparam int unsigned SCHED_STARVATION_WIDTH = 8;

  localparam int unsigned QUEUE_OCCUPANCY_LSB = 0;
  localparam int unsigned QUEUE_OCCUPANCY_WIDTH = 8;
  localparam int unsigned QUEUE_HIGH_WATER_LSB = 8;
  localparam int unsigned QUEUE_HIGH_WATER_WIDTH = 8;
  localparam int unsigned QUEUE_FULL_BIT = 16;
  localparam int unsigned QUEUE_EMPTY_BIT = 17;

  function automatic logic is_legal_offset(input reg_offset_t offset);
    case (offset)
      REG_SOC_ID:        return 1'b1;
      REG_VERSION:       return 1'b1;
      REG_CTRL:          return 1'b1;
      REG_STATUS:        return 1'b1;
      REG_IRQ_STATUS:    return 1'b1;
      REG_IRQ_ENABLE:    return 1'b1;
      REG_TIMER_CTRL:    return 1'b1;
      REG_TIMER_VALUE:   return 1'b1;
      REG_DMA_SRC_ADDR:  return 1'b1;
      REG_DMA_DST_ADDR:  return 1'b1;
      REG_DMA_LEN_BYTES: return 1'b1;
      REG_DMA_CTRL:      return 1'b1;
      REG_DMA_STATUS:    return 1'b1;
      REG_CMD_OPCODE:    return 1'b1;
      REG_CMD_SRC0_ADDR: return 1'b1;
      REG_CMD_SRC1_ADDR: return 1'b1;
      REG_CMD_DST_ADDR:  return 1'b1;
      REG_CMD_LEN:       return 1'b1;
      REG_CMD_M:         return 1'b1;
      REG_CMD_N:         return 1'b1;
      REG_CMD_K:         return 1'b1;
      REG_CMD_FLAGS:     return 1'b1;
      REG_CMD_PRIORITY:  return 1'b1;
      REG_CMD_SUBMIT:    return 1'b1;
      REG_CMD_STATUS:    return 1'b1;
      REG_PERF_SELECT:   return 1'b1;
      REG_PERF_VALUE:    return 1'b1;
      REG_PERF_VALUE_HI: return 1'b1;
      REG_ERROR_STATUS:  return 1'b1;
      REG_CMD_ID:        return 1'b1;
      REG_SCHED_CTRL:    return 1'b1;
      REG_QUEUE_STATUS:  return 1'b1;
      default:           return 1'b0;
    endcase
  endfunction

  function automatic logic is_read_only_offset(input reg_offset_t offset);
    case (offset)
      REG_SOC_ID:        return 1'b1;
      REG_VERSION:       return 1'b1;
      REG_STATUS:        return 1'b1;
      REG_TIMER_VALUE:   return 1'b1;
      REG_PERF_VALUE:    return 1'b1;
      REG_PERF_VALUE_HI: return 1'b1;
      REG_QUEUE_STATUS:  return 1'b1;
      default:           return 1'b0;
    endcase
  endfunction

  function automatic logic is_write_only_offset(input reg_offset_t offset);
    return (offset == REG_CMD_SUBMIT);
  endfunction

endpackage
