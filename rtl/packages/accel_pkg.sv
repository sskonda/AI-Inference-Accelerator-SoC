package accel_pkg;

  import soc_pkg::*;

  localparam int unsigned OPCODE_WIDTH = 4;
  localparam int unsigned ELEMENT_WIDTH = 16;
  localparam int unsigned ACCUM_WIDTH = 40;
  localparam int unsigned LENGTH_WIDTH = 16;
  localparam int unsigned DIMENSION_WIDTH = 8;
  localparam int unsigned FLAGS_WIDTH = 8;
  localparam int unsigned PRIORITY_WIDTH = 3;
  localparam int unsigned COMMAND_ID_WIDTH = 16;
  localparam int unsigned SCHEDULER_POLICY_WIDTH = 2;

  localparam int unsigned FLAG_SIGNED_BIT = 0;
  localparam int unsigned FLAG_SATURATE_BIT = 1;
  localparam int unsigned FLAG_IRQ_ON_DONE_BIT = 2;

  typedef enum logic [OPCODE_WIDTH-1:0] {
    CMD_OP_INVALID = 4'h0,
    CMD_OP_DMA_COPY = 4'h1,
    CMD_OP_VECTOR_ADD = 4'h2,
    CMD_OP_VECTOR_MULTIPLY = 4'h3,
    CMD_OP_VECTOR_SCALE = 4'h4,
    CMD_OP_VECTOR_RELU = 4'h5,
    CMD_OP_VECTOR_CLAMP = 4'h6,
    CMD_OP_REDUCE_SUM = 4'h7,
    CMD_OP_REDUCE_MAX = 4'h8,
    CMD_OP_GEMM = 4'h9
  } command_opcode_e;

  typedef enum logic [SCHEDULER_POLICY_WIDTH-1:0] {
    SCHED_ROUND_ROBIN = 2'b00,
    SCHED_PRIORITY_FIRST = 2'b01
  } scheduler_policy_e;

  typedef struct packed {
    command_opcode_e opcode;
    addr_t src0_addr;
    addr_t src1_addr;
    addr_t dst_addr;
    logic [LENGTH_WIDTH-1:0] length;
    logic [DIMENSION_WIDTH-1:0] m;
    logic [DIMENSION_WIDTH-1:0] n;
    logic [DIMENSION_WIDTH-1:0] k;
    logic [FLAGS_WIDTH-1:0] flags;
    logic [PRIORITY_WIDTH-1:0] priority_level;
    logic [COMMAND_ID_WIDTH-1:0] command_id;
  } command_desc_t;

  typedef struct packed {
    logic [COMMAND_ID_WIDTH-1:0] command_id;
    command_opcode_e opcode;
    error_e error;
    logic [DATA_WIDTH-1:0] result;
    logic [DATA_WIDTH-1:0] cycles;
  } command_response_t;

  function automatic logic is_valid_opcode(input command_opcode_e opcode);
    case (opcode)
      CMD_OP_DMA_COPY, CMD_OP_VECTOR_ADD, CMD_OP_VECTOR_MULTIPLY, CMD_OP_VECTOR_SCALE,
          CMD_OP_VECTOR_RELU, CMD_OP_VECTOR_CLAMP, CMD_OP_REDUCE_SUM, CMD_OP_REDUCE_MAX,
          CMD_OP_GEMM:
      return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic is_vector_opcode(input command_opcode_e opcode);
    case (opcode)
      CMD_OP_VECTOR_ADD, CMD_OP_VECTOR_MULTIPLY, CMD_OP_VECTOR_SCALE, CMD_OP_VECTOR_RELU,
          CMD_OP_VECTOR_CLAMP:
      return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic is_reduction_opcode(input command_opcode_e opcode);
    return (opcode == CMD_OP_REDUCE_SUM) || (opcode == CMD_OP_REDUCE_MAX);
  endfunction

endpackage
