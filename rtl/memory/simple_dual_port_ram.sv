module simple_dual_port_ram #(
    parameter int unsigned DATA_WIDTH = soc_pkg::DATA_WIDTH,
    parameter int unsigned ADDR_WIDTH = soc_pkg::DEFAULT_RAM_ADDR_WIDTH,
    parameter bit REGISTER_OUTPUT = 1'b0,
    parameter string INIT_FILE = ""
) (
  input  logic                                           clk,
  input  logic                                           rst_n,
  input  logic                                           rd_en,
  input  logic [                         ADDR_WIDTH-1:0] rd_addr,
  output logic                                           rd_valid,
  output logic [                         DATA_WIDTH-1:0] rd_data,
  input  logic                                           wr_en,
  input  logic [                         ADDR_WIDTH-1:0] wr_addr,
  input  logic [                         DATA_WIDTH-1:0] wr_data,
  input  logic [(DATA_WIDTH/soc_pkg::BITS_PER_BYTE)-1:0] wr_strb
);

  localparam int unsigned DEPTH = 2 ** ADDR_WIDTH;
  localparam int unsigned STRB_WIDTH = DATA_WIDTH / soc_pkg::BITS_PER_BYTE;

  logic [DATA_WIDTH-1:0] memory         [DEPTH];
  logic [DATA_WIDTH-1:0] ram_read_data;
  logic                  ram_read_valid;

  initial begin : initialize_and_validate
    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % soc_pkg::BITS_PER_BYTE) != 0)) begin
      $fatal(1, "RAM data width must contain a positive whole number of bytes");
    end
    if (ADDR_WIDTH == 0) begin
      $fatal(1, "RAM address width must be positive");
    end
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, memory);
    end
  end

  always_ff @(posedge clk) begin
    for (int unsigned byte_index = 0; byte_index < STRB_WIDTH; byte_index++) begin
      if (wr_en && wr_strb[byte_index]) begin
        memory[wr_addr][byte_index*soc_pkg::BITS_PER_BYTE+:soc_pkg::BITS_PER_BYTE] <=
            wr_data[byte_index*soc_pkg::BITS_PER_BYTE+:soc_pkg::BITS_PER_BYTE];
      end
    end
    if (rd_en) begin
      ram_read_data <= memory[rd_addr];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ram_read_valid <= 1'b0;
    end else begin
      ram_read_valid <= rd_en;
    end
  end

  if (REGISTER_OUTPUT) begin : gen_registered_output
    always_ff @(posedge clk) begin
      if (ram_read_valid) begin
        rd_data <= ram_read_data;
      end
    end

    always_ff @(posedge clk) begin
      if (!rst_n) begin
        rd_valid <= 1'b0;
      end else begin
        rd_valid <= ram_read_valid;
      end
    end
  end else begin : gen_ram_output
    always_comb begin
      rd_valid = ram_read_valid;
      rd_data  = ram_read_data;
    end
  end

`ifndef SYNTHESIS
  task automatic load_hex(input string file_name);
    $readmemh(file_name, memory);
  endtask

  task automatic fill_memory(input logic [DATA_WIDTH-1:0] value);
    for (int unsigned word_index = 0; word_index < DEPTH; word_index++) begin
      memory[word_index] = value;
    end
  endtask
`endif

  property p_known_control;
    @(posedge clk) disable iff (!rst_n) !$isunknown(
        {rd_en, rd_valid, wr_en, wr_strb}
    );
  endproperty

  property p_reset_clears_read_valid;
    @(posedge clk) !rst_n |=> !rd_valid;
  endproperty

  a_known_control :
  assert property (p_known_control);
  a_reset_clears_read_valid :
  assert property (p_reset_clears_read_valid);

endmodule
