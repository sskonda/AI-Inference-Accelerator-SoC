`timescale 1ns/1ps

module artifact_primitive_tb;
  import soc_pkg::*;

  localparam logic [ADDR_WIDTH-1:0] LOCAL_SPM_BASE = SPM_BASE_ADDR;
  localparam int unsigned LOCAL_SPM_SIZE_BYTES = 64;

  logic clk;
  logic rst_n;

  logic fifo_push_valid;
  logic fifo_push_ready;
  logic [7:0] fifo_push_data;
  logic fifo_pop_valid;
  logic fifo_pop_ready;
  logic [7:0] fifo_pop_data;
  logic fifo_full;
  logic fifo_empty;
  logic [2:0] fifo_occupancy;

  logic fifo_one_push_valid;
  logic fifo_one_push_ready;
  logic [7:0] fifo_one_push_data;
  logic fifo_one_pop_valid;
  logic fifo_one_pop_ready;
  logic [7:0] fifo_one_pop_data;
  logic fifo_one_full;
  logic fifo_one_empty;
  logic fifo_one_occupancy;

  logic fifo_three_push_valid;
  logic fifo_three_push_ready;
  logic [7:0] fifo_three_push_data;
  logic fifo_three_pop_valid;
  logic fifo_three_pop_ready;
  logic [7:0] fifo_three_pop_data;
  logic fifo_three_full;
  logic fifo_three_empty;
  logic [1:0] fifo_three_occupancy;

  logic skid_input_valid;
  logic skid_input_ready;
  logic [7:0] skid_input_data;
  logic skid_output_valid;
  logic skid_output_ready;
  logic [7:0] skid_output_data;

  logic ram_rd_en;
  logic [2:0] ram_rd_addr;
  logic ram_rd_valid;
  logic [31:0] ram_rd_data;
  logic ram_reg_rd_valid;
  logic [31:0] ram_reg_rd_data;
  logic ram_wr_en;
  logic [2:0] ram_wr_addr;
  logic [31:0] ram_wr_data;
  logic [3:0] ram_wr_strb;

  logic spm_rd_en;
  logic [31:0] spm_rd_addr;
  logic spm_rd_valid;
  logic [31:0] spm_rd_data;
  logic spm_rd_error;
  logic spm_wr_en;
  logic [31:0] spm_wr_addr;
  logic [31:0] spm_wr_data;
  logic [3:0] spm_wr_strb;
  logic spm_wr_error;
  logic [31:0] definition_checksum;

  logic [7:0] phase;
  integer trace_fd;

  primitive_test_top dut (
      .clk(clk),
      .rst_n(rst_n),
      .fifo_push_valid(fifo_push_valid),
      .fifo_push_ready(fifo_push_ready),
      .fifo_push_data(fifo_push_data),
      .fifo_pop_valid(fifo_pop_valid),
      .fifo_pop_ready(fifo_pop_ready),
      .fifo_pop_data(fifo_pop_data),
      .fifo_full(fifo_full),
      .fifo_empty(fifo_empty),
      .fifo_occupancy(fifo_occupancy),
      .fifo_one_push_valid(fifo_one_push_valid),
      .fifo_one_push_ready(fifo_one_push_ready),
      .fifo_one_push_data(fifo_one_push_data),
      .fifo_one_pop_valid(fifo_one_pop_valid),
      .fifo_one_pop_ready(fifo_one_pop_ready),
      .fifo_one_pop_data(fifo_one_pop_data),
      .fifo_one_full(fifo_one_full),
      .fifo_one_empty(fifo_one_empty),
      .fifo_one_occupancy(fifo_one_occupancy),
      .fifo_three_push_valid(fifo_three_push_valid),
      .fifo_three_push_ready(fifo_three_push_ready),
      .fifo_three_push_data(fifo_three_push_data),
      .fifo_three_pop_valid(fifo_three_pop_valid),
      .fifo_three_pop_ready(fifo_three_pop_ready),
      .fifo_three_pop_data(fifo_three_pop_data),
      .fifo_three_full(fifo_three_full),
      .fifo_three_empty(fifo_three_empty),
      .fifo_three_occupancy(fifo_three_occupancy),
      .skid_input_valid(skid_input_valid),
      .skid_input_ready(skid_input_ready),
      .skid_input_data(skid_input_data),
      .skid_output_valid(skid_output_valid),
      .skid_output_ready(skid_output_ready),
      .skid_output_data(skid_output_data),
      .ram_rd_en(ram_rd_en),
      .ram_rd_addr(ram_rd_addr),
      .ram_rd_valid(ram_rd_valid),
      .ram_rd_data(ram_rd_data),
      .ram_reg_rd_valid(ram_reg_rd_valid),
      .ram_reg_rd_data(ram_reg_rd_data),
      .ram_wr_en(ram_wr_en),
      .ram_wr_addr(ram_wr_addr),
      .ram_wr_data(ram_wr_data),
      .ram_wr_strb(ram_wr_strb),
      .spm_rd_en(spm_rd_en),
      .spm_rd_addr(spm_rd_addr),
      .spm_rd_valid(spm_rd_valid),
      .spm_rd_data(spm_rd_data),
      .spm_rd_error(spm_rd_error),
      .spm_wr_en(spm_wr_en),
      .spm_wr_addr(spm_wr_addr),
      .spm_wr_data(spm_wr_data),
      .spm_wr_strb(spm_wr_strb),
      .spm_wr_error(spm_wr_error),
      .definition_checksum(definition_checksum)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic check(input logic condition, input string message);
    if (!condition) begin
      $display("FAIL primitive: %s at %0t", message, $time);
      $fatal(1);
    end
  endtask

  task automatic tick;
    @(posedge clk);
    #1;
  endtask

  task automatic clear_inputs;
    begin
      fifo_push_valid = 1'b0;
      fifo_push_data = '0;
      fifo_pop_ready = 1'b0;
      fifo_one_push_valid = 1'b0;
      fifo_one_push_data = '0;
      fifo_one_pop_ready = 1'b0;
      fifo_three_push_valid = 1'b0;
      fifo_three_push_data = '0;
      fifo_three_pop_ready = 1'b0;
      skid_input_valid = 1'b0;
      skid_input_data = '0;
      skid_output_ready = 1'b0;
      ram_rd_en = 1'b0;
      ram_rd_addr = '0;
      ram_wr_en = 1'b0;
      ram_wr_addr = '0;
      ram_wr_data = '0;
      ram_wr_strb = '0;
      spm_rd_en = 1'b0;
      spm_rd_addr = '0;
      spm_wr_en = 1'b0;
      spm_wr_addr = '0;
      spm_wr_data = '0;
      spm_wr_strb = '0;
    end
  endtask

  task automatic reset_dut;
    begin
      clear_inputs();
      rst_n = 1'b0;
      repeat (3) tick();
      rst_n = 1'b1;
      tick();
    end
  endtask

  task automatic push_fifo(input logic [7:0] value);
    begin
      fifo_push_valid = 1'b1;
      fifo_push_data = value;
      fifo_pop_ready = 1'b0;
      #1;
      check(fifo_push_ready, "FIFO rejected legal push");
      tick();
      fifo_push_valid = 1'b0;
      fifo_push_data = '0;
      #1;
    end
  endtask

  task automatic pop_fifo(input logic [7:0] expected);
    begin
      fifo_pop_ready = 1'b1;
      #1;
      check(fifo_pop_valid, "FIFO did not present queued data");
      check(fifo_pop_data == expected, "FIFO ordering mismatch");
      tick();
      fifo_pop_ready = 1'b0;
      #1;
    end
  endtask

  task automatic write_ram(input logic [2:0] address, input logic [31:0] data,
                           input logic [3:0] strobe);
    begin
      ram_wr_en = 1'b1;
      ram_wr_addr = address;
      ram_wr_data = data;
      ram_wr_strb = strobe;
      tick();
      ram_wr_en = 1'b0;
      ram_wr_strb = '0;
      #1;
    end
  endtask

  task automatic read_ram(input logic [2:0] address, output logic [31:0] data);
    begin
      ram_rd_en = 1'b1;
      ram_rd_addr = address;
      tick();
      check(ram_rd_valid, "unregistered RAM read valid missing");
      data = ram_rd_data;
      check(!ram_reg_rd_valid, "registered RAM valid arrived too early");
      ram_rd_en = 1'b0;
      tick();
      check(ram_reg_rd_valid, "registered RAM read valid missing");
      check(ram_reg_rd_data == data, "registered RAM data mismatch");
    end
  endtask

  always @(posedge clk) begin
    if (trace_fd != 0) begin
      $fdisplay(
          trace_fd,
          "%0t,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0h,%0h,%0d,%0h,%0d,%0d",
          $time,
          phase,
          rst_n,
          fifo_push_valid,
          fifo_push_ready,
          fifo_pop_valid,
          fifo_pop_ready,
          fifo_full,
          fifo_empty,
          fifo_occupancy,
          fifo_pop_data,
          ram_rd_data,
          ram_rd_valid,
          ram_reg_rd_data,
          spm_wr_error,
          spm_rd_error
      );
    end
  end

  initial begin
    logic [31:0] ram_value;

    trace_fd = $fopen("Images/traces/primitive_trace.csv", "w");
    $fdisplay(trace_fd, "time,phase,rst_n,fifo_push_valid,fifo_push_ready,fifo_pop_valid,fifo_pop_ready,fifo_full,fifo_empty,fifo_occupancy,fifo_pop_data,ram_rd_data,ram_rd_valid,ram_reg_rd_data,spm_wr_error,spm_rd_error");

    phase = 8'h01;
    reset_dut();
    check(fifo_empty && !fifo_full && fifo_occupancy == 0, "FIFO reset state incorrect");

    phase = 8'h10;
    push_fifo(8'h11);
    push_fifo(8'h22);
    push_fifo(8'h33);
    push_fifo(8'h44);
    check(fifo_full && !fifo_empty && fifo_occupancy == 4, "FIFO full state incorrect");

    fifo_push_valid = 1'b1;
    fifo_push_data = 8'h55;
    fifo_pop_ready = 1'b0;
    #1;
    check(!fifo_push_ready, "FIFO accepted push while full");
    tick();
    fifo_pop_ready = 1'b1;
    #1;
    check(fifo_push_ready && fifo_pop_valid && fifo_pop_data == 8'h11,
           "FIFO simultaneous push/pop failed");
    tick();
    fifo_push_valid = 1'b0;
    fifo_pop_ready = 1'b0;
    pop_fifo(8'h22);
    pop_fifo(8'h33);
    pop_fifo(8'h44);
    pop_fifo(8'h55);
    check(fifo_empty && !fifo_full && fifo_occupancy == 0, "FIFO did not empty");

    phase = 8'h20;
    reset_dut();
    fifo_one_push_valid = 1'b1;
    fifo_one_push_data = 8'h31;
    tick();
    check(fifo_one_full && fifo_one_pop_valid && fifo_one_pop_data == 8'h31,
           "depth-one FIFO did not retain first item");
    fifo_one_push_data = 8'h62;
    fifo_one_pop_ready = 1'b1;
    #1;
    check(fifo_one_push_ready && fifo_one_pop_data == 8'h31,
           "depth-one FIFO replacement handshake failed");
    tick();
    fifo_one_push_valid = 1'b0;
    fifo_one_pop_ready = 1'b0;
    check(fifo_one_full && fifo_one_pop_data == 8'h62,
           "depth-one FIFO replacement value missing");
    fifo_one_pop_ready = 1'b1;
    tick();
    fifo_one_pop_ready = 1'b0;
    check(fifo_one_empty, "depth-one FIFO did not empty");

    phase = 8'h30;
    reset_dut();
    fifo_three_push_valid = 1'b1;
    fifo_three_push_data = 8'h17;
    tick();
    fifo_three_push_data = 8'h29;
    tick();
    fifo_three_push_data = 8'h3b;
    tick();
    fifo_three_push_valid = 1'b0;
    check(fifo_three_full && fifo_three_occupancy == 3, "depth-three FIFO did not fill");
    fifo_three_pop_ready = 1'b1;
    #1;
    check(fifo_three_pop_valid && fifo_three_pop_data == 8'h17, "depth-three order item 0");
    tick();
    check(fifo_three_pop_valid && fifo_three_pop_data == 8'h29, "depth-three order item 1");
    tick();
    check(fifo_three_pop_valid && fifo_three_pop_data == 8'h3b, "depth-three order item 2");
    tick();
    fifo_three_pop_ready = 1'b0;
    check(fifo_three_empty, "depth-three FIFO did not empty");

    phase = 8'h40;
    reset_dut();
    skid_input_valid = 1'b1;
    skid_input_data = 8'h12;
    skid_output_ready = 1'b1;
    #1;
    check(skid_input_ready && skid_output_valid && skid_output_data == 8'h12,
           "skid pass-through failed");
    tick();
    skid_input_data = 8'h34;
    skid_output_ready = 1'b0;
    tick();
    skid_input_valid = 1'b0;
    #1;
    check(skid_output_valid && skid_output_data == 8'h34, "skid hold failed");
    skid_output_ready = 1'b1;
    tick();
    skid_output_ready = 1'b0;

    phase = 8'h50;
    reset_dut();
    write_ram(3'd1, 32'h11223344, 4'hf);
    read_ram(3'd1, ram_value);
    check(ram_value == 32'h11223344, "RAM write/read mismatch");
    write_ram(3'd1, 32'haabbccdd, 4'h5);
    read_ram(3'd1, ram_value);
    check(ram_value == 32'h11bb33dd, "RAM byte-enable write mismatch");
    write_ram(3'd2, 32'hcafebabe, 4'hf);
    ram_rd_en = 1'b1;
    ram_rd_addr = 3'd2;
    ram_wr_en = 1'b1;
    ram_wr_addr = 3'd2;
    ram_wr_data = 32'h0badf00d;
    ram_wr_strb = 4'hf;
    tick();
    check(ram_rd_valid && ram_rd_data == 32'hcafebabe, "RAM collision not read-first");
    ram_rd_en = 1'b0;
    ram_wr_en = 1'b0;
    ram_wr_strb = '0;
    tick();
    read_ram(3'd2, ram_value);
    check(ram_value == 32'h0badf00d, "RAM collision write missing");

    phase = 8'h60;
    reset_dut();
    spm_wr_en = 1'b1;
    spm_wr_addr = LOCAL_SPM_BASE + 32'h10;
    spm_wr_data = 32'h2468ace0;
    spm_wr_strb = 4'hf;
    #1;
    check(!spm_wr_error, "scratchpad legal write rejected");
    tick();
    spm_wr_en = 1'b0;
    spm_rd_en = 1'b1;
    spm_rd_addr = LOCAL_SPM_BASE + 32'h10;
    #1;
    check(!spm_rd_error, "scratchpad legal read rejected");
    tick();
    check(spm_rd_valid && spm_rd_data == 32'h2468ace0, "scratchpad data mismatch");
    spm_rd_en = 1'b0;

    spm_wr_en = 1'b1;
    spm_wr_addr = LOCAL_SPM_BASE + LOCAL_SPM_SIZE_BYTES;
    spm_wr_strb = 4'hf;
    #1;
    check(spm_wr_error, "scratchpad accepted out-of-bounds write");
    tick();
    spm_wr_en = 1'b0;

    spm_rd_en = 1'b1;
    spm_rd_addr = LOCAL_SPM_BASE + 32'h1;
    #1;
    check(spm_rd_error, "scratchpad accepted misaligned read");
    tick();
    spm_rd_en = 1'b0;

    phase = 8'hff;
    repeat (4) tick();
    $display("PASS artifact_primitive_tb fifo_depths skid_buffer ram scratchpad");
    $fclose(trace_fd);
    $finish;
  end
endmodule
