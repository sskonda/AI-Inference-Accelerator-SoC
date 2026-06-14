module scratchpad_ram #(
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH,
    parameter int unsigned SIZE_BYTES = soc_pkg::SPM_SIZE_BYTES,
    parameter logic [soc_pkg::ADDR_WIDTH-1:0] BASE_ADDR = soc_pkg::SPM_BASE_ADDR,
    parameter bit REGISTER_OUTPUT = 1'b0
) (
  input  logic                                           clk,
  input  logic                                           rst_n,
  input  logic                                           rd_en,
  input  logic [                soc_pkg::ADDR_WIDTH-1:0] rd_addr,
  output logic                                           rd_valid,
  output logic [                         DATA_WIDTH-1:0] rd_data,
  output logic                                           rd_error,
  input  logic                                           wr_en,
  input  logic [                soc_pkg::ADDR_WIDTH-1:0] wr_addr,
  input  logic [                         DATA_WIDTH-1:0] wr_data,
  input  logic [(DATA_WIDTH/soc_pkg::BITS_PER_BYTE)-1:0] wr_strb,
  output logic                                           wr_error
);

  localparam int unsigned DATA_BYTES = DATA_WIDTH / soc_pkg::BITS_PER_BYTE;
  localparam int unsigned BYTE_OFFSET_WIDTH = $clog2(DATA_BYTES);
  localparam int unsigned WORD_COUNT = SIZE_BYTES / DATA_BYTES;
  localparam int unsigned RAM_ADDR_WIDTH = soc_pkg::width_for_index(WORD_COUNT);

  logic                      ram_rd_en;
  logic                      ram_wr_en;
  logic [RAM_ADDR_WIDTH-1:0] ram_rd_addr;
  logic [RAM_ADDR_WIDTH-1:0] ram_wr_addr;

  function automatic logic access_is_legal(input logic [soc_pkg::ADDR_WIDTH-1:0] address);
    logic [soc_pkg::ADDR_WIDTH:0] byte_offset;
    logic [soc_pkg::ADDR_WIDTH:0] data_bytes_extended;
    logic [soc_pkg::ADDR_WIDTH:0] maximum_byte_offset;

    byte_offset = {1'b0, address} - {1'b0, BASE_ADDR};
    data_bytes_extended = (soc_pkg::ADDR_WIDTH + 1)'(DATA_BYTES);
    maximum_byte_offset = (soc_pkg::ADDR_WIDTH + 1)'(SIZE_BYTES - DATA_BYTES);
    return ({1'b0, address} >= {1'b0, BASE_ADDR}) && (byte_offset <= maximum_byte_offset) &&
        ((byte_offset % data_bytes_extended) == '0);
  endfunction

  initial begin : validate_parameters
    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % soc_pkg::BITS_PER_BYTE) != 0)) begin
      $fatal(1, "Scratchpad data width must contain a positive whole number of bytes");
    end
    if ((SIZE_BYTES < DATA_BYTES) || ((SIZE_BYTES % DATA_BYTES) != 0)) begin
      $fatal(1, "Scratchpad size must contain a positive whole number of words");
    end
    if ((DATA_BYTES & (DATA_BYTES - 1)) != 0) begin
      $fatal(1, "Scratchpad word size must be a power of two");
    end
    if ((WORD_COUNT & (WORD_COUNT - 1)) != 0) begin
      $fatal(1, "Scratchpad word count must be a power of two");
    end
  end

  always_comb begin
    rd_error = rd_en && !access_is_legal(rd_addr);
    wr_error = wr_en && !access_is_legal(wr_addr);
    ram_rd_en = rd_en && !rd_error;
    ram_wr_en = wr_en && !wr_error;
    ram_rd_addr = RAM_ADDR_WIDTH'((rd_addr - BASE_ADDR) >> BYTE_OFFSET_WIDTH);
    ram_wr_addr = RAM_ADDR_WIDTH'((wr_addr - BASE_ADDR) >> BYTE_OFFSET_WIDTH);
  end

  simple_dual_port_ram #(
      .DATA_WIDTH     (DATA_WIDTH),
      .ADDR_WIDTH     (RAM_ADDR_WIDTH),
      .REGISTER_OUTPUT(REGISTER_OUTPUT)
  ) u_ram (
      .clk     (clk),
      .rst_n   (rst_n),
      .rd_en   (ram_rd_en),
      .rd_addr (ram_rd_addr),
      .rd_valid(rd_valid),
      .rd_data (rd_data),
      .wr_en   (ram_wr_en),
      .wr_addr (ram_wr_addr),
      .wr_data (wr_data),
      .wr_strb (wr_strb)
  );

  property p_illegal_read_blocked;
    @(posedge clk) disable iff (!rst_n) rd_en && rd_error |-> !ram_rd_en;
  endproperty

  property p_illegal_write_blocked;
    @(posedge clk) disable iff (!rst_n) wr_en && wr_error |-> !ram_wr_en;
  endproperty

  a_illegal_read_blocked :
  assert property (p_illegal_read_blocked);
  a_illegal_write_blocked :
  assert property (p_illegal_write_blocked);

endmodule
