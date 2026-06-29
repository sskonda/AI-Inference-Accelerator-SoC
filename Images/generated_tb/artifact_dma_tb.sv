`timescale 1ns/1ps

module artifact_dma_tb;
  import soc_pkg::*;

  logic clk;
  logic rst_n;

  logic start;
  logic [ADDR_WIDTH-1:0] source_address;
  logic [ADDR_WIDTH-1:0] destination_address;
  logic [BYTE_COUNT_WIDTH-1:0] length_bytes;
  logic start_accepted;
  logic start_rejected;
  logic busy;
  logic done;
  logic error;
  logic [ERROR_WIDTH-1:0] error_code;

  logic source_req_valid;
  logic source_req_ready;
  logic source_req_write;
  logic [ADDR_WIDTH-1:0] source_req_addr;
  logic [DATA_WIDTH-1:0] source_req_wdata;
  logic [STRB_WIDTH-1:0] source_req_wstrb;
  logic source_req_last;
  logic source_rsp_valid;
  logic source_rsp_ready;
  logic [DATA_WIDTH-1:0] source_rsp_rdata;
  logic source_rsp_error;

  logic destination_req_valid;
  logic destination_req_ready;
  logic destination_req_write;
  logic [ADDR_WIDTH-1:0] destination_req_addr;
  logic [DATA_WIDTH-1:0] destination_req_wdata;
  logic [STRB_WIDTH-1:0] destination_req_wstrb;
  logic destination_req_last;
  logic destination_rsp_valid;
  logic destination_rsp_ready;
  logic [DATA_WIDTH-1:0] destination_rsp_rdata;
  logic destination_rsp_error;

  logic active_cycle;
  logic stalled_cycle;
  logic [BYTE_COUNT_WIDTH-1:0] bytes_read_event;
  logic [BYTE_COUNT_WIDTH-1:0] bytes_written_event;
  logic [DATA_WIDTH-1:0] definition_checksum;

  logic [7:0] phase;
  integer trace_fd;
  integer cycle_count;
  integer src_req_count;
  integer dst_req_count;
  integer src_last_count;
  integer dst_last_count;
  integer stall_count;
  integer bytes_read_total;
  integer bytes_written_total;
  logic [DATA_WIDTH-1:0] last_source_word;
  logic [STRB_WIDTH-1:0] last_dst_strobe;
  logic [DATA_WIDTH-1:0] last_dst_data;

  logic source_ready_enable;
  logic destination_ready_enable;
  integer source_ready_modulus;
  integer source_ready_block_residue;
  integer destination_ready_modulus;
  integer destination_ready_block_residue;
  logic source_fail_next;
  logic destination_fail_next;

  dma_test_top dut (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .source_address(source_address),
      .destination_address(destination_address),
      .length_bytes(length_bytes),
      .start_accepted(start_accepted),
      .start_rejected(start_rejected),
      .busy(busy),
      .done(done),
      .error(error),
      .error_code(error_code),
      .source_req_valid(source_req_valid),
      .source_req_ready(source_req_ready),
      .source_req_write(source_req_write),
      .source_req_addr(source_req_addr),
      .source_req_wdata(source_req_wdata),
      .source_req_wstrb(source_req_wstrb),
      .source_req_last(source_req_last),
      .source_rsp_valid(source_rsp_valid),
      .source_rsp_ready(source_rsp_ready),
      .source_rsp_rdata(source_rsp_rdata),
      .source_rsp_error(source_rsp_error),
      .destination_req_valid(destination_req_valid),
      .destination_req_ready(destination_req_ready),
      .destination_req_write(destination_req_write),
      .destination_req_addr(destination_req_addr),
      .destination_req_wdata(destination_req_wdata),
      .destination_req_wstrb(destination_req_wstrb),
      .destination_req_last(destination_req_last),
      .destination_rsp_valid(destination_rsp_valid),
      .destination_rsp_ready(destination_rsp_ready),
      .destination_rsp_rdata(destination_rsp_rdata),
      .destination_rsp_error(destination_rsp_error),
      .active_cycle(active_cycle),
      .stalled_cycle(stalled_cycle),
      .bytes_read_event(bytes_read_event),
      .bytes_written_event(bytes_written_event),
      .definition_checksum(definition_checksum)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  assign source_req_ready = source_ready_enable &&
      ((source_ready_modulus == 0) ||
       ((cycle_count % source_ready_modulus) != source_ready_block_residue));
  assign destination_req_ready = destination_ready_enable &&
      ((destination_ready_modulus == 0) ||
       ((cycle_count % destination_ready_modulus) != destination_ready_block_residue));

  function automatic logic [DATA_WIDTH-1:0] source_pattern(input logic [ADDR_WIDTH-1:0] addr);
    source_pattern = 32'h5a00_0000 ^ addr ^ {addr[15:0], addr[31:16]};
  endfunction

  function automatic integer strobe_byte_count(input logic [STRB_WIDTH-1:0] strobe);
    integer index;
    begin
      strobe_byte_count = 0;
      for (index = 0; index < STRB_WIDTH; index = index + 1) begin
        if (strobe[index]) begin
          strobe_byte_count = strobe_byte_count + 1;
        end
      end
    end
  endfunction

  task automatic check(input logic condition, input string message);
    if (!condition) begin
      $display("FAIL dma: %s at %0t", message, $time);
      $fatal(1);
    end
  endtask

  task automatic tick;
    @(posedge clk);
    #1;
  endtask

  task automatic clear_inputs;
    begin
      start = 1'b0;
      source_address = '0;
      destination_address = '0;
      length_bytes = '0;
    end
  endtask

  task automatic clear_model;
    begin
      source_ready_enable = 1'b1;
      destination_ready_enable = 1'b1;
      source_ready_modulus = 0;
      source_ready_block_residue = 0;
      destination_ready_modulus = 0;
      destination_ready_block_residue = 0;
      source_fail_next = 1'b0;
      destination_fail_next = 1'b0;
      source_rsp_valid = 1'b0;
      source_rsp_rdata = '0;
      source_rsp_error = 1'b0;
      destination_rsp_valid = 1'b0;
      destination_rsp_rdata = '0;
      destination_rsp_error = 1'b0;
      src_req_count = 0;
      dst_req_count = 0;
      src_last_count = 0;
      dst_last_count = 0;
      stall_count = 0;
      bytes_read_total = 0;
      bytes_written_total = 0;
      last_source_word = '0;
      last_dst_strobe = '0;
      last_dst_data = '0;
      cycle_count = 0;
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

  task automatic start_transfer(input logic [ADDR_WIDTH-1:0] src,
                                input logic [ADDR_WIDTH-1:0] dst,
                                input logic [BYTE_COUNT_WIDTH-1:0] len);
    begin
      source_address = src;
      destination_address = dst;
      length_bytes = len;
      start = 1'b1;
      tick();
      start = 1'b0;
      #1;
    end
  endtask

  task automatic wait_for_done;
    integer wait_cycle;
    begin
      wait_cycle = 0;
      while (!done && wait_cycle < 512) begin
        tick();
        wait_cycle = wait_cycle + 1;
      end
      check(done, "DMA transfer timed out");
    end
  endtask

  always @(posedge clk) begin
    if (!rst_n) begin
      source_rsp_valid <= 1'b0;
      source_rsp_error <= 1'b0;
      source_rsp_rdata <= '0;
      destination_rsp_valid <= 1'b0;
      destination_rsp_error <= 1'b0;
      destination_rsp_rdata <= '0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (stalled_cycle) begin
        stall_count <= stall_count + 1;
      end
      if (bytes_read_event != 0) begin
        bytes_read_total <= bytes_read_total + bytes_read_event;
      end
      if (bytes_written_event != 0) begin
        bytes_written_total <= bytes_written_total + bytes_written_event;
      end

      if (source_rsp_valid && source_rsp_ready) begin
        source_rsp_valid <= 1'b0;
        source_rsp_error <= 1'b0;
      end
      if (destination_rsp_valid && destination_rsp_ready) begin
        destination_rsp_valid <= 1'b0;
        destination_rsp_error <= 1'b0;
      end

      if (source_req_valid && source_req_ready) begin
        check(!source_req_write, "source port issued a write");
        check(source_req_wstrb == '0, "source port used byte strobes");
        source_rsp_valid <= 1'b1;
        source_rsp_rdata <= source_pattern(source_req_addr);
        source_rsp_error <= source_fail_next;
        last_source_word <= source_pattern(source_req_addr);
        source_fail_next <= 1'b0;
        src_req_count <= src_req_count + 1;
        if (source_req_last) begin
          src_last_count <= src_last_count + 1;
        end
      end

      if (destination_req_valid && destination_req_ready) begin
        check(destination_req_write, "destination port issued a read");
        check(destination_req_wstrb != '0, "destination write used empty strobe");
        if (!destination_fail_next) begin
          check(destination_req_wdata == last_source_word, "destination data differed from source response");
        end
        destination_rsp_valid <= 1'b1;
        destination_rsp_rdata <= '0;
        destination_rsp_error <= destination_fail_next;
        destination_fail_next <= 1'b0;
        dst_req_count <= dst_req_count + 1;
        last_dst_strobe <= destination_req_wstrb;
        last_dst_data <= destination_req_wdata;
        if (destination_req_last) begin
          dst_last_count <= dst_last_count + 1;
        end
      end
    end
  end

  always @(posedge clk) begin
    if (trace_fd != 0) begin
      $fdisplay(
          trace_fd,
          "%0t,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0h,%0d,%0d,%0h,%0d,%0d,%0d,%0h,%0d,%0d,%0d,%0d,%0d",
          $time,
          phase,
          rst_n,
          start,
          start_accepted,
          start_rejected,
          busy,
          done,
          error_code,
          error,
          stalled_cycle,
          length_bytes,
          source_req_valid,
          source_req_ready,
          source_req_last,
          source_rsp_rdata,
          destination_req_valid,
          destination_req_ready,
          destination_req_last,
          destination_req_wstrb,
          destination_rsp_error
      );
    end
  end

  initial begin
    integer before_src;
    integer before_dst;

    trace_fd = $fopen("Images/traces/dma_trace.csv", "w");
    $fdisplay(trace_fd, "time,phase,rst_n,start,start_accepted,start_rejected,busy,done,error_code,error,stalled_cycle,length_bytes,source_req_valid,source_req_ready,source_req_last,source_rsp_rdata,destination_req_valid,destination_req_ready,destination_req_last,destination_req_wstrb,destination_rsp_error");

    phase = 8'h01;
    reset_dut();

    phase = 8'h10;
    start_transfer(DRAM_BASE_ADDR + 32'h100, SPM_BASE_ADDR + 32'h200, 24'd4);
    check(start_accepted, "one-word transfer was not accepted");
    wait_for_done();
    check(!error && error_code == ERR_NONE, "one-word transfer returned error");
    check(src_req_count == 1 && dst_req_count == 1, "one-word request count mismatch");
    check(last_dst_strobe == 4'hf, "one-word final strobe mismatch");

    phase = 8'h20;
    reset_dut();
    start_transfer(DRAM_BASE_ADDR + 32'h400, SPM_BASE_ADDR + 32'h800, 24'd19);
    wait_for_done();
    check(!error && src_req_count == 5 && dst_req_count == 5, "partial transfer count mismatch");
    check(last_dst_strobe == 4'h7, "partial transfer final strobe mismatch");
    check(src_last_count == 2 && dst_last_count == 2, "partial logical burst boundary mismatch");

    phase = 8'h30;
    reset_dut();
    source_ready_modulus = 3;
    source_ready_block_residue = 0;
    destination_ready_modulus = 4;
    destination_ready_block_residue = 1;
    start_transfer(DRAM_BASE_ADDR + 32'h1000, SPM_BASE_ADDR + 32'h1400, 24'd16);
    wait_for_done();
    check(!error && stall_count != 0, "backpressure did not create stall cycles");

    phase = 8'h40;
    reset_dut();
    start_transfer(32'h0, 32'h0, 24'd0);
    check(start_accepted && done && !error, "zero-length transfer did not complete as no-op");
    check(src_req_count == 0 && dst_req_count == 0, "zero-length transfer accessed memory");

    phase = 8'h50;
    reset_dut();
    start_transfer(DRAM_BASE_ADDR + 32'h1, SPM_BASE_ADDR, 24'd4);
    check(done && error && error_code == ERR_ADDRESS, "unaligned source was not rejected");
    check(src_req_count == 0 && dst_req_count == 0, "illegal address issued memory traffic");

    phase = 8'h60;
    reset_dut();
    source_ready_enable = 1'b0;
    start_transfer(DRAM_BASE_ADDR + 32'h2800, SPM_BASE_ADDR + 32'h2c00, 24'd16);
    check(start_accepted && busy, "busy rejection setup transfer did not start");
    before_src = src_req_count;
    before_dst = dst_req_count;
    source_address = DRAM_BASE_ADDR + 32'h2900;
    destination_address = SPM_BASE_ADDR + 32'h2d00;
    length_bytes = 24'd4;
    start = 1'b1;
    tick();
    start = 1'b0;
    check(start_rejected && error && error_code == ERR_DMA_BUSY && busy,
          "start while busy was not rejected");
    check(src_req_count == before_src && dst_req_count == before_dst,
          "busy rejection issued unexpected traffic");
    source_ready_enable = 1'b1;
    wait_for_done();
    check(!error, "original transfer failed after busy rejection");

    phase = 8'h70;
    reset_dut();
    source_fail_next = 1'b1;
    start_transfer(DRAM_BASE_ADDR + 32'h3000, SPM_BASE_ADDR + 32'h3100, 24'd4);
    wait_for_done();
    check(error && error_code == ERR_ADDRESS && src_req_count == 1 && dst_req_count == 0,
          "source response error did not terminate correctly");

    phase = 8'h80;
    reset_dut();
    destination_fail_next = 1'b1;
    start_transfer(DRAM_BASE_ADDR + 32'h3400, SPM_BASE_ADDR + 32'h3500, 24'd4);
    wait_for_done();
    check(error && error_code == ERR_ADDRESS && src_req_count == 1 && dst_req_count == 1,
          "destination response error did not terminate correctly");

    phase = 8'h90;
    reset_dut();
    source_ready_enable = 1'b0;
    start_transfer(DRAM_BASE_ADDR + 32'h3800, SPM_BASE_ADDR + 32'h3900, 24'd16);
    check(busy && source_req_valid, "reset test did not reach active transfer");
    rst_n = 1'b0;
    repeat (2) tick();
    check(!busy && !done && !error, "reset did not clear DMA control state");
    rst_n = 1'b1;
    source_ready_enable = 1'b1;
    repeat (2) tick();

    phase = 8'hff;
    repeat (4) tick();
    $display("PASS artifact_dma_tb normal partial backpressure zero illegal busy errors reset");
    $fclose(trace_fd);
    $finish;
  end
endmodule
