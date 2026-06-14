package soc_pkg;

  localparam int unsigned BITS_PER_BYTE = 8;
  localparam int unsigned BYTE_COUNT_WIDTH = 24;
  localparam int unsigned BYTES_PER_KIB = 1024;

  localparam int unsigned ADDR_WIDTH = 32;
  localparam int unsigned DATA_WIDTH = 32;
  localparam int unsigned DATA_BYTES = DATA_WIDTH / BITS_PER_BYTE;
  localparam int unsigned STRB_WIDTH = DATA_BYTES;
  localparam int unsigned WORD_ADDRESS_LSB = $clog2(DATA_BYTES);
  localparam int unsigned AXIL_ADDR_WIDTH = 12;
  localparam int unsigned AXIL_RESP_WIDTH = 2;
  localparam int unsigned ERROR_WIDTH = 4;
  localparam int unsigned PERF_COUNTER_ID_WIDTH = 4;
  localparam int unsigned PERF_COUNTER_WIDTH = 64;
  localparam int unsigned ERROR_STATUS_WIDTH = DATA_WIDTH;
  localparam int unsigned DEFAULT_STREAM_USER_WIDTH = 1;
  localparam int unsigned DEFAULT_FIFO_DEPTH = 8;
  localparam int unsigned DEFAULT_COMMAND_QUEUE_DEPTH = 8;
  localparam int unsigned DEFAULT_RAM_ADDR_WIDTH = 10;
  localparam int unsigned DEFAULT_DMA_BURST_BEATS = 4;

  localparam int unsigned MMIO_SIZE_KIB = 4;
  localparam int unsigned SPM_SIZE_KIB = 64;
  localparam int unsigned DRAM_SIZE_KIB = 1024;
  localparam int unsigned MMIO_SIZE_BYTES = MMIO_SIZE_KIB * BYTES_PER_KIB;
  localparam int unsigned SPM_SIZE_BYTES = SPM_SIZE_KIB * BYTES_PER_KIB;
  localparam int unsigned DRAM_SIZE_BYTES = DRAM_SIZE_KIB * BYTES_PER_KIB;

  localparam logic [ADDR_WIDTH-1:0] MMIO_BASE_ADDR = 32'h0000_0000;
  localparam logic [ADDR_WIDTH-1:0] SPM_BASE_ADDR = 32'h1000_0000;
  localparam logic [ADDR_WIDTH-1:0] DRAM_BASE_ADDR = 32'h8000_0000;

  localparam int unsigned IRQ_SOURCE_COUNT = 5;
  localparam int unsigned IRQ_DMA_DONE_BIT = 0;
  localparam int unsigned IRQ_CMD_DONE_BIT = 1;
  localparam int unsigned IRQ_ACCEL_DONE_BIT = 2;
  localparam int unsigned IRQ_ERROR_BIT = 3;
  localparam int unsigned IRQ_TIMER_BIT = 4;

  typedef logic [ADDR_WIDTH-1:0] addr_t;
  typedef logic [DATA_WIDTH-1:0] data_t;
  typedef logic [STRB_WIDTH-1:0] strb_t;
  typedef logic [BYTE_COUNT_WIDTH-1:0] byte_count_t;

  function automatic int unsigned width_for_count(input int unsigned maximum_value);
    return (maximum_value < 2) ? 1 : $clog2(maximum_value + 1);
  endfunction

  function automatic int unsigned width_for_index(input int unsigned item_count);
    return (item_count < 2) ? 1 : $clog2(item_count);
  endfunction

  typedef enum logic [AXIL_RESP_WIDTH-1:0] {
    AXIL_RESP_OKAY   = 2'b00,
    AXIL_RESP_SLVERR = 2'b10
  } axil_resp_e;

  typedef enum logic {
    MEM_READ  = 1'b0,
    MEM_WRITE = 1'b1
  } mem_direction_e;

  typedef enum logic [ERROR_WIDTH-1:0] {
    ERR_NONE = 4'h0,
    ERR_ILLEGAL_MMIO = 4'h1,
    ERR_READ_ONLY = 4'h2,
    ERR_DMA_BUSY = 4'h3,
    ERR_DMA_LENGTH = 4'h4,
    ERR_ADDRESS = 4'h5,
    ERR_QUEUE_FULL = 4'h6,
    ERR_OPCODE = 4'h7,
    ERR_DIMENSION = 4'h8,
    ERR_SPM_BOUNDS = 4'h9,
    ERR_INTERNAL = 4'hf
  } error_e;

  typedef enum logic [PERF_COUNTER_ID_WIDTH-1:0] {
    PERF_TOTAL_CYCLES = 4'h0,
    PERF_DMA_ACTIVE_CYCLES = 4'h1,
    PERF_DMA_STALLED_CYCLES = 4'h2,
    PERF_ACCEL_ACTIVE_CYCLES = 4'h3,
    PERF_ACCEL_STALLED_CYCLES = 4'h4,
    PERF_QUEUE_HIGH_WATER = 4'h5,
    PERF_COMMANDS_COMPLETED = 4'h6,
    PERF_BYTES_READ = 4'h7,
    PERF_BYTES_WRITTEN = 4'h8,
    PERF_IRQ_LATENCY = 4'h9,
    PERF_SCHEDULER_STALLS = 4'ha,
    PERF_COUNTER_INVALID = 4'hf
  } perf_counter_id_e;

  function automatic logic address_in_region(input addr_t address, input addr_t region_base,
                                             input int unsigned region_size_bytes);
    logic [ADDR_WIDTH:0] region_limit;

    region_limit = {1'b0, region_base} + region_size_bytes;
    return ({1'b0, address} >= {1'b0, region_base}) && ({1'b0, address} < region_limit);
  endfunction

  function automatic logic is_mmio_address(input addr_t address);
    return address_in_region(address, MMIO_BASE_ADDR, MMIO_SIZE_BYTES);
  endfunction

  function automatic logic is_spm_address(input addr_t address);
    return address_in_region(address, SPM_BASE_ADDR, SPM_SIZE_BYTES);
  endfunction

  function automatic logic is_dram_address(input addr_t address);
    return address_in_region(address, DRAM_BASE_ADDR, DRAM_SIZE_BYTES);
  endfunction

  function automatic logic is_data_address(input addr_t address);
    return is_spm_address(address) || is_dram_address(address);
  endfunction

  function automatic logic data_range_is_legal(input addr_t address,
                                               input byte_count_t length_bytes);
    logic  [ADDR_WIDTH:0] end_address;
    addr_t                final_address;

    if (length_bytes == '0) begin
      return 1'b1;
    end

    end_address = {1'b0, address} + (ADDR_WIDTH + 1)'(length_bytes) - 1'b1;
    if (end_address[ADDR_WIDTH]) begin
      return 1'b0;
    end

    final_address = addr_t'(end_address);
    return (is_spm_address(
        address
    ) && is_spm_address(
        final_address
    )) || (is_dram_address(
        address
    ) && is_dram_address(
        final_address
    ));
  endfunction

endpackage
