module primitive_test_top #(
    parameter int unsigned TEST_DATA_WIDTH = 8,
    parameter int unsigned FIFO_DEPTH = 4,
    parameter int unsigned FIFO_COUNT_WIDTH = soc_pkg::width_for_count(FIFO_DEPTH),
    parameter int unsigned FIFO_NON_POWER_OF_TWO_DEPTH = 3,
    parameter int unsigned RAM_DATA_WIDTH = soc_pkg::DATA_WIDTH,
    parameter int unsigned RAM_ADDR_WIDTH = 3,
    parameter int unsigned RAM_STRB_WIDTH = RAM_DATA_WIDTH / soc_pkg::BITS_PER_BYTE,
    parameter int unsigned TEST_SPM_SIZE_BYTES = 64
) (
  input  logic                                                             clk,
  input  logic                                                             rst_n,
  input  logic                                                             fifo_push_valid,
  output logic                                                             fifo_push_ready,
  input  logic [                                      TEST_DATA_WIDTH-1:0] fifo_push_data,
  output logic                                                             fifo_pop_valid,
  input  logic                                                             fifo_pop_ready,
  output logic [                                      TEST_DATA_WIDTH-1:0] fifo_pop_data,
  output logic                                                             fifo_full,
  output logic                                                             fifo_empty,
  output logic [                                     FIFO_COUNT_WIDTH-1:0] fifo_occupancy,
  input  logic                                                             fifo_one_push_valid,
  output logic                                                             fifo_one_push_ready,
  input  logic [                                      TEST_DATA_WIDTH-1:0] fifo_one_push_data,
  output logic                                                             fifo_one_pop_valid,
  input  logic                                                             fifo_one_pop_ready,
  output logic [                                      TEST_DATA_WIDTH-1:0] fifo_one_pop_data,
  output logic                                                             fifo_one_full,
  output logic                                                             fifo_one_empty,
  output logic [                          soc_pkg::width_for_count(1)-1:0] fifo_one_occupancy,
  input  logic                                                             fifo_three_push_valid,
  output logic                                                             fifo_three_push_ready,
  input  logic [                                      TEST_DATA_WIDTH-1:0] fifo_three_push_data,
  output logic                                                             fifo_three_pop_valid,
  input  logic                                                             fifo_three_pop_ready,
  output logic [                                      TEST_DATA_WIDTH-1:0] fifo_three_pop_data,
  output logic                                                             fifo_three_full,
  output logic                                                             fifo_three_empty,
  output logic [soc_pkg::width_for_count(FIFO_NON_POWER_OF_TWO_DEPTH)-1:0] fifo_three_occupancy,
  input  logic                                                             skid_input_valid,
  output logic                                                             skid_input_ready,
  input  logic [                                      TEST_DATA_WIDTH-1:0] skid_input_data,
  output logic                                                             skid_output_valid,
  input  logic                                                             skid_output_ready,
  output logic [                                      TEST_DATA_WIDTH-1:0] skid_output_data,
  input  logic                                                             ram_rd_en,
  input  logic [                                       RAM_ADDR_WIDTH-1:0] ram_rd_addr,
  output logic                                                             ram_rd_valid,
  output logic [                                       RAM_DATA_WIDTH-1:0] ram_rd_data,
  output logic                                                             ram_reg_rd_valid,
  output logic [                                       RAM_DATA_WIDTH-1:0] ram_reg_rd_data,
  input  logic                                                             ram_wr_en,
  input  logic [                                       RAM_ADDR_WIDTH-1:0] ram_wr_addr,
  input  logic [                                       RAM_DATA_WIDTH-1:0] ram_wr_data,
  input  logic [                                       RAM_STRB_WIDTH-1:0] ram_wr_strb,
  input  logic                                                             spm_rd_en,
  input  logic [                                  soc_pkg::ADDR_WIDTH-1:0] spm_rd_addr,
  output logic                                                             spm_rd_valid,
  output logic [                                       RAM_DATA_WIDTH-1:0] spm_rd_data,
  output logic                                                             spm_rd_error,
  input  logic                                                             spm_wr_en,
  input  logic [                                  soc_pkg::ADDR_WIDTH-1:0] spm_wr_addr,
  input  logic [                                       RAM_DATA_WIDTH-1:0] spm_wr_data,
  input  logic [                                       RAM_STRB_WIDTH-1:0] spm_wr_strb,
  output logic                                                             spm_wr_error,
  output logic [                                  soc_pkg::DATA_WIDTH-1:0] definition_checksum
);

  protocol_compile_top u_protocol_compile (
      .clk                (clk),
      .rst_n              (rst_n),
      .definition_checksum(definition_checksum)
  );

  sync_fifo #(
      .DATA_WIDTH(TEST_DATA_WIDTH),
      .DEPTH     (FIFO_DEPTH)
  ) u_fifo (
      .clk       (clk),
      .rst_n     (rst_n),
      .push_valid(fifo_push_valid),
      .push_ready(fifo_push_ready),
      .push_data (fifo_push_data),
      .pop_valid (fifo_pop_valid),
      .pop_ready (fifo_pop_ready),
      .pop_data  (fifo_pop_data),
      .full      (fifo_full),
      .empty     (fifo_empty),
      .occupancy (fifo_occupancy)
  );

  sync_fifo #(
      .DATA_WIDTH(TEST_DATA_WIDTH),
      .DEPTH     (1)
  ) u_fifo_one (
      .clk       (clk),
      .rst_n     (rst_n),
      .push_valid(fifo_one_push_valid),
      .push_ready(fifo_one_push_ready),
      .push_data (fifo_one_push_data),
      .pop_valid (fifo_one_pop_valid),
      .pop_ready (fifo_one_pop_ready),
      .pop_data  (fifo_one_pop_data),
      .full      (fifo_one_full),
      .empty     (fifo_one_empty),
      .occupancy (fifo_one_occupancy)
  );

  sync_fifo #(
      .DATA_WIDTH(TEST_DATA_WIDTH),
      .DEPTH     (FIFO_NON_POWER_OF_TWO_DEPTH)
  ) u_fifo_three (
      .clk       (clk),
      .rst_n     (rst_n),
      .push_valid(fifo_three_push_valid),
      .push_ready(fifo_three_push_ready),
      .push_data (fifo_three_push_data),
      .pop_valid (fifo_three_pop_valid),
      .pop_ready (fifo_three_pop_ready),
      .pop_data  (fifo_three_pop_data),
      .full      (fifo_three_full),
      .empty     (fifo_three_empty),
      .occupancy (fifo_three_occupancy)
  );

  skid_buffer #(
      .DATA_WIDTH(TEST_DATA_WIDTH)
  ) u_skid_buffer (
      .clk         (clk),
      .rst_n       (rst_n),
      .input_valid (skid_input_valid),
      .input_ready (skid_input_ready),
      .input_data  (skid_input_data),
      .output_valid(skid_output_valid),
      .output_ready(skid_output_ready),
      .output_data (skid_output_data)
  );

  simple_dual_port_ram #(
      .DATA_WIDTH     (RAM_DATA_WIDTH),
      .ADDR_WIDTH     (RAM_ADDR_WIDTH),
      .REGISTER_OUTPUT(1'b0)
  ) u_ram (
      .clk     (clk),
      .rst_n   (rst_n),
      .rd_en   (ram_rd_en),
      .rd_addr (ram_rd_addr),
      .rd_valid(ram_rd_valid),
      .rd_data (ram_rd_data),
      .wr_en   (ram_wr_en),
      .wr_addr (ram_wr_addr),
      .wr_data (ram_wr_data),
      .wr_strb (ram_wr_strb)
  );

  simple_dual_port_ram #(
      .DATA_WIDTH     (RAM_DATA_WIDTH),
      .ADDR_WIDTH     (RAM_ADDR_WIDTH),
      .REGISTER_OUTPUT(1'b1)
  ) u_registered_ram (
      .clk     (clk),
      .rst_n   (rst_n),
      .rd_en   (ram_rd_en),
      .rd_addr (ram_rd_addr),
      .rd_valid(ram_reg_rd_valid),
      .rd_data (ram_reg_rd_data),
      .wr_en   (ram_wr_en),
      .wr_addr (ram_wr_addr),
      .wr_data (ram_wr_data),
      .wr_strb (ram_wr_strb)
  );

  scratchpad_ram #(
      .DATA_WIDTH     (RAM_DATA_WIDTH),
      .SIZE_BYTES     (TEST_SPM_SIZE_BYTES),
      .REGISTER_OUTPUT(1'b0)
  ) u_scratchpad (
      .clk     (clk),
      .rst_n   (rst_n),
      .rd_en   (spm_rd_en),
      .rd_addr (spm_rd_addr),
      .rd_valid(spm_rd_valid),
      .rd_data (spm_rd_data),
      .rd_error(spm_rd_error),
      .wr_en   (spm_wr_en),
      .wr_addr (spm_wr_addr),
      .wr_data (spm_wr_data),
      .wr_strb (spm_wr_strb),
      .wr_error(spm_wr_error)
  );

endmodule
