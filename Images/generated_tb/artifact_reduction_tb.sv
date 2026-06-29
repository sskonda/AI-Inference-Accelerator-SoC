`timescale 1ns/1ps

module artifact_reduction_tb;
  import soc_pkg::*;
  import accel_pkg::*;

  localparam int unsigned SPM_WORDS = SPM_SIZE_BYTES / DATA_BYTES;
  localparam logic [ADDR_WIDTH-1:0] SRC_BASE = SPM_BASE_ADDR + 32'h4000;
  localparam logic [ADDR_WIDTH-1:0] DST_BASE = SPM_BASE_ADDR + 32'h6000;

  logic clk;
  logic rst_n;

  logic command_valid;
  logic command_ready;
  logic [OPCODE_WIDTH-1:0] command_opcode;
  logic [ADDR_WIDTH-1:0] command_src0_addr;
  logic [ADDR_WIDTH-1:0] command_dst_addr;
  logic [LENGTH_WIDTH-1:0] command_length;
  logic [FLAGS_WIDTH-1:0] command_flags;
  logic [COMMAND_ID_WIDTH-1:0] command_id;

  logic response_valid;
  logic response_ready;
  logic [COMMAND_ID_WIDTH-1:0] response_command_id;
  logic [OPCODE_WIDTH-1:0] response_opcode;
  logic [ERROR_WIDTH-1:0] response_error;
  logic [DATA_WIDTH-1:0] response_result;
  logic [DATA_WIDTH-1:0] response_cycles;

  logic memory_req_valid;
  logic memory_req_ready;
  logic memory_req_write;
  logic [ADDR_WIDTH-1:0] memory_req_addr;
  logic [DATA_WIDTH-1:0] memory_req_wdata;
  logic [STRB_WIDTH-1:0] memory_req_wstrb;
  logic memory_req_last;
  logic memory_rsp_valid;
  logic memory_rsp_ready;
  logic [DATA_WIDTH-1:0] memory_rsp_rdata;
  logic memory_rsp_error;

  logic busy;
  logic done;
  logic error;
  logic [ERROR_WIDTH-1:0] error_code;
  logic active_cycle;
  logic stalled_cycle;
  logic [LENGTH_WIDTH-1:0] elements_completed_event;
  logic [DATA_WIDTH-1:0] definition_checksum;

  logic [DATA_WIDTH-1:0] spm [0:SPM_WORDS-1];
  logic [7:0] phase;
  integer trace_fd;
  integer cycle_count;
  integer read_count;
  integer write_count;
  integer stall_count;
  logic ready_enable;
  integer ready_modulus;
  integer ready_block_residue;
  logic fail_next_read;
  logic fail_next_write;
  logic [STRB_WIDTH-1:0] last_write_strobe;

  reduction_test_top dut (
      .clk(clk),
      .rst_n(rst_n),
      .command_valid(command_valid),
      .command_ready(command_ready),
      .command_opcode(command_opcode),
      .command_src0_addr(command_src0_addr),
      .command_dst_addr(command_dst_addr),
      .command_length(command_length),
      .command_flags(command_flags),
      .command_id(command_id),
      .response_valid(response_valid),
      .response_ready(response_ready),
      .response_command_id(response_command_id),
      .response_opcode(response_opcode),
      .response_error(response_error),
      .response_result(response_result),
      .response_cycles(response_cycles),
      .memory_req_valid(memory_req_valid),
      .memory_req_ready(memory_req_ready),
      .memory_req_write(memory_req_write),
      .memory_req_addr(memory_req_addr),
      .memory_req_wdata(memory_req_wdata),
      .memory_req_wstrb(memory_req_wstrb),
      .memory_req_last(memory_req_last),
      .memory_rsp_valid(memory_rsp_valid),
      .memory_rsp_ready(memory_rsp_ready),
      .memory_rsp_rdata(memory_rsp_rdata),
      .memory_rsp_error(memory_rsp_error),
      .busy(busy),
      .done(done),
      .error(error),
      .error_code(error_code),
      .active_cycle(active_cycle),
      .stalled_cycle(stalled_cycle),
      .elements_completed_event(elements_completed_event),
      .definition_checksum(definition_checksum)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  assign memory_req_ready = ready_enable &&
      ((ready_modulus == 0) || ((cycle_count % ready_modulus) != ready_block_residue));

  function automatic int unsigned word_index(input logic [ADDR_WIDTH-1:0] address);
    word_index = (address - SPM_BASE_ADDR) >> WORD_ADDRESS_LSB;
  endfunction

  function automatic logic [DATA_WIDTH-1:0] read_word(input logic [ADDR_WIDTH-1:0] address,
                                                      output logic legal);
    int unsigned index;
    begin
      legal = is_spm_address(address) && ((address % DATA_BYTES) == 0) &&
          (word_index(address) < SPM_WORDS);
      if (legal) begin
        index = word_index(address);
        read_word = spm[index];
      end else begin
        read_word = '0;
      end
    end
  endfunction

  task automatic write_word(input logic [ADDR_WIDTH-1:0] address, input logic [DATA_WIDTH-1:0] data,
                            input logic [STRB_WIDTH-1:0] strobe, output logic legal);
    int unsigned index;
    int unsigned byte_index;
    begin
      legal = is_spm_address(address) && ((address % DATA_BYTES) == 0) &&
          (word_index(address) < SPM_WORDS);
      if (legal) begin
        index = word_index(address);
        for (byte_index = 0; byte_index < DATA_BYTES; byte_index = byte_index + 1) begin
          if (strobe[byte_index]) begin
            spm[index][byte_index*BITS_PER_BYTE+:BITS_PER_BYTE] =
                data[byte_index*BITS_PER_BYTE+:BITS_PER_BYTE];
          end
        end
      end
    end
  endtask

  task automatic write_element(input logic [ADDR_WIDTH-1:0] base, input int unsigned element_index,
                               input logic [ELEMENT_WIDTH-1:0] value);
    int unsigned word;
    int unsigned lane;
    begin
      word = word_index(base + element_index * (ELEMENT_WIDTH / BITS_PER_BYTE));
      lane = element_index % (DATA_WIDTH / ELEMENT_WIDTH);
      spm[word][lane*ELEMENT_WIDTH+:ELEMENT_WIDTH] = value;
    end
  endtask

  function automatic logic [ELEMENT_WIDTH-1:0] read_element(input logic [ADDR_WIDTH-1:0] base,
                                                           input int unsigned element_index);
    int unsigned word;
    int unsigned lane;
    begin
      word = word_index(base + element_index * (ELEMENT_WIDTH / BITS_PER_BYTE));
      lane = element_index % (DATA_WIDTH / ELEMENT_WIDTH);
      read_element = spm[word][lane*ELEMENT_WIDTH+:ELEMENT_WIDTH];
    end
  endfunction

  task automatic check(input logic condition, input string message);
    if (!condition) begin
      $display("FAIL reduction: %s at %0t", message, $time);
      $fatal(1);
    end
  endtask

  task automatic tick;
    @(posedge clk);
    #1;
  endtask

  task automatic clear_inputs;
    begin
      command_valid = 1'b0;
      command_opcode = CMD_OP_REDUCE_SUM;
      command_src0_addr = SRC_BASE;
      command_dst_addr = DST_BASE;
      command_length = 1;
      command_flags = '0;
      command_id = 16'ha00;
      response_ready = 1'b0;
    end
  endtask

  task automatic clear_model;
    int unsigned index;
    begin
      for (index = 0; index < SPM_WORDS; index = index + 1) begin
        spm[index] = '0;
      end
      memory_rsp_valid = 1'b0;
      memory_rsp_rdata = '0;
      memory_rsp_error = 1'b0;
      ready_enable = 1'b1;
      ready_modulus = 0;
      ready_block_residue = 0;
      fail_next_read = 1'b0;
      fail_next_write = 1'b0;
      cycle_count = 0;
      read_count = 0;
      write_count = 0;
      stall_count = 0;
      last_write_strobe = '0;
    end
  endtask

  task automatic reset_dut;
    begin
      clear_inputs();
      clear_model();
      rst_n = 1'b0;
      repeat (3) tick();
      rst_n = 1'b1;
      tick();
    end
  endtask

  task automatic run_command(input logic [OPCODE_WIDTH-1:0] opcode,
                             input logic [LENGTH_WIDTH-1:0] length,
                             input logic [FLAGS_WIDTH-1:0] flags,
                             input logic [COMMAND_ID_WIDTH-1:0] id,
                             input logic [ERROR_WIDTH-1:0] expected_error,
                             input logic [DATA_WIDTH-1:0] expected_result);
    integer wait_cycle;
    begin
      command_opcode = opcode;
      command_src0_addr = SRC_BASE;
      command_dst_addr = DST_BASE;
      command_length = length;
      command_flags = flags;
      command_id = id;
      command_valid = 1'b1;
      #1;
      check(command_ready, "command was not ready at launch");
      tick();
      command_valid = 1'b0;
      wait_cycle = 0;
      while (!response_valid && wait_cycle < 1000) begin
        tick();
        wait_cycle = wait_cycle + 1;
      end
      check(response_valid, "response timed out");
      check(response_command_id == id, "response command ID mismatch");
      check(response_error == expected_error, "unexpected response error");
      if (expected_error == ERR_NONE) begin
        check(response_result == expected_result, "response result mismatch");
      end
      response_ready = 1'b1;
      tick();
      response_ready = 1'b0;
      check(!busy, "reduction unit did not retire");
    end
  endtask

  always @(posedge clk) begin
    if (!rst_n) begin
      memory_rsp_valid <= 1'b0;
      memory_rsp_error <= 1'b0;
      memory_rsp_rdata <= '0;
    end else begin
      logic legal;
      logic [DATA_WIDTH-1:0] data;

      cycle_count <= cycle_count + 1;
      if (stalled_cycle) begin
        stall_count <= stall_count + 1;
      end
      if (memory_rsp_valid && memory_rsp_ready) begin
        memory_rsp_valid <= 1'b0;
        memory_rsp_error <= 1'b0;
      end
      if (memory_req_valid && memory_req_ready) begin
        if (memory_req_write) begin
          write_word(memory_req_addr, memory_req_wdata, memory_req_wstrb, legal);
          write_count <= write_count + 1;
          last_write_strobe <= memory_req_wstrb;
          memory_rsp_rdata <= '0;
          memory_rsp_error <= fail_next_write || !legal;
          fail_next_write <= 1'b0;
        end else begin
          data = read_word(memory_req_addr, legal);
          read_count <= read_count + 1;
          memory_rsp_rdata <= data;
          memory_rsp_error <= fail_next_read || !legal;
          fail_next_read <= 1'b0;
        end
        memory_rsp_valid <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    if (trace_fd != 0) begin
      $fdisplay(
          trace_fd,
          "%0t,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0h,%0d,%0h,%0h,%0d,%0d,%0d,%0h,%0h,%0d,%0d,%0d,%0d",
          $time,
          phase,
          rst_n,
          command_valid,
          command_ready,
          busy,
          done,
          error,
          error_code,
          response_valid,
          response_error,
          response_result,
          memory_req_valid,
          memory_req_ready,
          memory_req_write,
          memory_req_addr,
          memory_req_wstrb,
          memory_rsp_valid,
          memory_rsp_ready,
          stalled_cycle,
          elements_completed_event
      );
    end
  end

  initial begin
    trace_fd = $fopen("Images/traces/reduction_trace.csv", "w");
    $fdisplay(trace_fd, "time,phase,rst_n,command_valid,command_ready,busy,done,error,error_code,response_valid,response_error,response_result,memory_req_valid,memory_req_ready,memory_req_write,memory_req_addr,memory_req_wstrb,memory_rsp_valid,memory_rsp_ready,stalled_cycle,elements_completed_event");

    phase = 8'h01;
    reset_dut();

    phase = 8'h10;
    write_element(SRC_BASE, 0, 16'd1);
    write_element(SRC_BASE, 1, 16'd2);
    write_element(SRC_BASE, 2, 16'd3);
    write_element(SRC_BASE, 3, 16'd4);
    write_element(SRC_BASE, 4, 16'd5);
    run_command(CMD_OP_REDUCE_SUM, 16'd5, 8'h00, 16'ha01, ERR_NONE, 32'd15);
    check(read_element(DST_BASE, 0) == 16'd15, "sum destination mismatch");
    check(last_write_strobe == 4'h3, "reduction result strobe mismatch");

    phase = 8'h20;
    reset_dut();
    write_element(SRC_BASE, 0, 16'd1);
    write_element(SRC_BASE, 1, 16'hffff);
    write_element(SRC_BASE, 2, 16'd9);
    write_element(SRC_BASE, 3, 16'd100);
    run_command(CMD_OP_REDUCE_MAX, 16'd4, 8'h00, 16'ha02, ERR_NONE, 32'h0000ffff);
    check(read_element(DST_BASE, 0) == 16'hffff, "max destination mismatch");

    phase = 8'h30;
    reset_dut();
    ready_modulus = 3;
    ready_block_residue = 2;
    write_element(SRC_BASE, 0, 16'd1);
    write_element(SRC_BASE, 1, 16'd2);
    write_element(SRC_BASE, 2, 16'd3);
    write_element(SRC_BASE, 3, 16'd4);
    write_element(SRC_BASE, 4, 16'd5);
    write_element(SRC_BASE, 5, 16'd6);
    write_element(SRC_BASE, 6, 16'd7);
    write_element(SRC_BASE, 7, 16'd8);
    write_element(SRC_BASE, 8, 16'd9);
    run_command(CMD_OP_REDUCE_SUM, 16'd9, 8'h00, 16'ha03, ERR_NONE, 32'd45);
    check(stall_count != 0, "reduction backpressure did not create stalls");

    phase = 8'h40;
    reset_dut();
    run_command(CMD_OP_VECTOR_ADD, 16'd4, 8'h00, 16'ha04, ERR_OPCODE, 32'd0);
    check(read_count == 0 && write_count == 0, "invalid reduction command issued memory traffic");

    phase = 8'h50;
    reset_dut();
    fail_next_read = 1'b1;
    write_element(SRC_BASE, 0, 16'd1);
    write_element(SRC_BASE, 1, 16'd2);
    run_command(CMD_OP_REDUCE_SUM, 16'd2, 8'h00, 16'ha05, ERR_ADDRESS, 32'd0);
    check(write_count == 0, "reduction read error should not write destination");

    phase = 8'h60;
    reset_dut();
    fail_next_write = 1'b1;
    write_element(SRC_BASE, 0, 16'd1);
    write_element(SRC_BASE, 1, 16'd2);
    run_command(CMD_OP_REDUCE_SUM, 16'd2, 8'h00, 16'ha06, ERR_ADDRESS, 32'd0);
    check(write_count == 1, "reduction write error path did not attempt result write");

    phase = 8'hff;
    repeat (4) tick();
    $display("PASS artifact_reduction_tb sum max backpressure invalid read_error write_error");
    $fclose(trace_fd);
    $finish;
  end
endmodule
