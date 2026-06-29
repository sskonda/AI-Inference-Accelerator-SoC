`timescale 1ns/1ps

module artifact_command_tb;
  import soc_pkg::*;
  import accel_pkg::*;

  logic clk;
  logic rst_n;
  logic execution_enable;

  logic push_valid;
  logic push_ready;
  logic [OPCODE_WIDTH-1:0] push_opcode;
  logic [ADDR_WIDTH-1:0] push_src0_addr;
  logic [ADDR_WIDTH-1:0] push_src1_addr;
  logic [ADDR_WIDTH-1:0] push_dst_addr;
  logic [LENGTH_WIDTH-1:0] push_length;
  logic [DIMENSION_WIDTH-1:0] push_m;
  logic [DIMENSION_WIDTH-1:0] push_n;
  logic [DIMENSION_WIDTH-1:0] push_k;
  logic [FLAGS_WIDTH-1:0] push_flags;
  logic [PRIORITY_WIDTH-1:0] push_priority;
  logic [COMMAND_ID_WIDTH-1:0] push_command_id;

  logic [SCHEDULER_POLICY_WIDTH-1:0] policy;
  logic [STARVATION_COUNTER_WIDTH-1:0] starvation_threshold;

  logic dma_cmd_ready;
  logic vector_cmd_ready;
  logic reduction_cmd_ready;
  logic gemm_cmd_ready;
  logic dma_cmd_valid;
  logic vector_cmd_valid;
  logic reduction_cmd_valid;
  logic gemm_cmd_valid;
  logic [OPCODE_WIDTH-1:0] dispatch_opcode;
  logic [COMMAND_ID_WIDTH-1:0] dispatch_command_id;
  logic [PRIORITY_WIDTH-1:0] dispatch_priority;
  logic [DATA_WIDTH-1:0] dma_command_checksum;
  logic [DATA_WIDTH-1:0] vector_command_checksum;
  logic [DATA_WIDTH-1:0] reduction_command_checksum;
  logic [DATA_WIDTH-1:0] gemm_command_checksum;

  logic completion_valid;
  logic [EXECUTOR_TARGET_WIDTH-1:0] completion_target;
  logic [COMMAND_ID_WIDTH-1:0] completion_command_id;
  logic [OPCODE_WIDTH-1:0] completion_opcode;
  logic [ERROR_WIDTH-1:0] completion_error;
  logic [DATA_WIDTH-1:0] completion_result;
  logic completion_ready;

  logic response_valid;
  logic response_ready;
  logic [COMMAND_ID_WIDTH-1:0] response_command_id;
  logic [OPCODE_WIDTH-1:0] response_opcode;
  logic [ERROR_WIDTH-1:0] response_error;
  logic [DATA_WIDTH-1:0] response_result;
  logic [DATA_WIDTH-1:0] response_cycles;

  logic queue_full;
  logic queue_empty;
  logic [3:0] queue_occupancy;
  logic [3:0] queue_high_water;
  logic selected_starved;
  logic processor_busy;
  logic scheduler_stalled;
  logic command_completed;
  logic command_error;
  logic [DATA_WIDTH-1:0] definition_checksum;

  logic [7:0] phase;
  integer trace_fd;

  command_test_top dut (
      .clk(clk),
      .rst_n(rst_n),
      .execution_enable(execution_enable),
      .push_valid(push_valid),
      .push_ready(push_ready),
      .push_opcode(push_opcode),
      .push_src0_addr(push_src0_addr),
      .push_src1_addr(push_src1_addr),
      .push_dst_addr(push_dst_addr),
      .push_length(push_length),
      .push_m(push_m),
      .push_n(push_n),
      .push_k(push_k),
      .push_flags(push_flags),
      .push_priority(push_priority),
      .push_command_id(push_command_id),
      .policy(policy),
      .starvation_threshold(starvation_threshold),
      .dma_cmd_ready(dma_cmd_ready),
      .vector_cmd_ready(vector_cmd_ready),
      .reduction_cmd_ready(reduction_cmd_ready),
      .gemm_cmd_ready(gemm_cmd_ready),
      .dma_cmd_valid(dma_cmd_valid),
      .vector_cmd_valid(vector_cmd_valid),
      .reduction_cmd_valid(reduction_cmd_valid),
      .gemm_cmd_valid(gemm_cmd_valid),
      .dispatch_opcode(dispatch_opcode),
      .dispatch_command_id(dispatch_command_id),
      .dispatch_priority(dispatch_priority),
      .dma_command_checksum(dma_command_checksum),
      .vector_command_checksum(vector_command_checksum),
      .reduction_command_checksum(reduction_command_checksum),
      .gemm_command_checksum(gemm_command_checksum),
      .completion_valid(completion_valid),
      .completion_target(completion_target),
      .completion_command_id(completion_command_id),
      .completion_opcode(completion_opcode),
      .completion_error(completion_error),
      .completion_result(completion_result),
      .completion_ready(completion_ready),
      .response_valid(response_valid),
      .response_ready(response_ready),
      .response_command_id(response_command_id),
      .response_opcode(response_opcode),
      .response_error(response_error),
      .response_result(response_result),
      .response_cycles(response_cycles),
      .queue_full(queue_full),
      .queue_empty(queue_empty),
      .queue_occupancy(queue_occupancy),
      .queue_high_water(queue_high_water),
      .selected_starved(selected_starved),
      .processor_busy(processor_busy),
      .scheduler_stalled(scheduler_stalled),
      .command_completed(command_completed),
      .command_error(command_error),
      .definition_checksum(definition_checksum)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic check(input logic condition, input string message);
    if (!condition) begin
      $display("FAIL command: %s at %0t", message, $time);
      $fatal(1);
    end
  endtask

  task automatic tick;
    @(posedge clk);
    #1;
  endtask

  task automatic clear_inputs;
    begin
      execution_enable = 1'b0;
      push_valid = 1'b0;
      push_opcode = CMD_OP_INVALID;
      push_src0_addr = SPM_BASE_ADDR;
      push_src1_addr = SPM_BASE_ADDR + 32'h100;
      push_dst_addr = SPM_BASE_ADDR + 32'h200;
      push_length = 16'd4;
      push_m = 8'd2;
      push_n = 8'd2;
      push_k = 8'd2;
      push_flags = '0;
      push_priority = '0;
      push_command_id = '0;
      policy = SCHED_ROUND_ROBIN;
      starvation_threshold = 8'd3;
      dma_cmd_ready = 1'b1;
      vector_cmd_ready = 1'b1;
      reduction_cmd_ready = 1'b1;
      gemm_cmd_ready = 1'b1;
      completion_valid = 1'b0;
      completion_target = EXEC_TARGET_INVALID;
      completion_command_id = '0;
      completion_opcode = CMD_OP_INVALID;
      completion_error = ERR_NONE;
      completion_result = '0;
      response_ready = 1'b0;
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

  task automatic push_command(input logic [OPCODE_WIDTH-1:0] opcode,
                              input logic [PRIORITY_WIDTH-1:0] prio,
                              input logic [COMMAND_ID_WIDTH-1:0] command_id);
    begin
      push_opcode = opcode;
      push_priority = prio;
      push_command_id = command_id;
      push_valid = 1'b1;
      #1;
      check(push_ready, "queue rejected legal push");
      tick();
      push_valid = 1'b0;
      #1;
    end
  endtask

  task automatic accept_response(input logic [COMMAND_ID_WIDTH-1:0] command_id,
                                 input logic [OPCODE_WIDTH-1:0] opcode,
                                 input logic [ERROR_WIDTH-1:0] expected_error);
    integer wait_cycle;
    begin
      wait_cycle = 0;
      while (!response_valid && wait_cycle < 32) begin
        tick();
        wait_cycle = wait_cycle + 1;
      end
      check(response_valid, "response did not arrive");
      check(response_command_id == command_id, "response command id mismatch");
      check(response_opcode == opcode, "response opcode mismatch");
      check(response_error == expected_error, "response error mismatch");
      response_ready = 1'b1;
      tick();
      response_ready = 1'b0;
    end
  endtask

  task automatic complete_command(input logic [EXECUTOR_TARGET_WIDTH-1:0] target,
                                  input logic [COMMAND_ID_WIDTH-1:0] command_id,
                                  input logic [OPCODE_WIDTH-1:0] opcode,
                                  input logic [ERROR_WIDTH-1:0] result_error);
    begin
      completion_target = target;
      completion_command_id = command_id;
      completion_opcode = opcode;
      completion_error = result_error;
      completion_result = 32'hca11_0000 | command_id;
      completion_valid = 1'b1;
      #1;
      check(completion_ready, "backend completion was not accepted");
      tick();
      completion_valid = 1'b0;
      accept_response(command_id, opcode, result_error);
    end
  endtask

  always @(posedge clk) begin
    if (trace_fd != 0) begin
      $fdisplay(
          trace_fd,
          "%0t,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0h",
          $time,
          phase,
          rst_n,
          execution_enable,
          push_valid,
          push_ready,
          queue_full,
          queue_empty,
          queue_occupancy,
          queue_high_water,
          dma_cmd_valid,
          vector_cmd_valid,
          reduction_cmd_valid,
          gemm_cmd_valid,
          completion_valid,
          completion_ready,
          response_valid,
          response_error,
          selected_starved,
          scheduler_stalled,
          response_result
      );
    end
  end

  initial begin
    integer index;

    trace_fd = $fopen("Images/traces/command_trace.csv", "w");
    $fdisplay(trace_fd, "time,phase,rst_n,execution_enable,push_valid,push_ready,queue_full,queue_empty,queue_occupancy,queue_high_water,dma_cmd_valid,vector_cmd_valid,reduction_cmd_valid,gemm_cmd_valid,completion_valid,completion_ready,response_valid,response_error,selected_starved,scheduler_stalled,response_result");

    phase = 8'h01;
    reset_dut();
    check(queue_empty && !queue_full, "queue reset state incorrect");

    phase = 8'h10;
    push_command(CMD_OP_DMA_COPY, 3'd1, 16'h0010);
    execution_enable = 1'b1;
    #1;
    check(dma_cmd_valid, "DMA command did not dispatch");
    tick();
    complete_command(EXEC_TARGET_DMA, 16'h0010, CMD_OP_DMA_COPY, ERR_NONE);

    phase = 8'h20;
    reset_dut();
    push_command(CMD_OP_INVALID, 3'd0, 16'h0020);
    execution_enable = 1'b1;
    tick();
    check(command_error, "invalid opcode did not flag command_error");
    accept_response(16'h0020, CMD_OP_INVALID, ERR_OPCODE);

    phase = 8'h30;
    reset_dut();
    vector_cmd_ready = 1'b0;
    push_command(CMD_OP_VECTOR_ADD, 3'd2, 16'h0030);
    execution_enable = 1'b1;
    #1;
    check(vector_cmd_valid && scheduler_stalled, "vector backpressure did not stall scheduler");
    vector_cmd_ready = 1'b1;
    #1;
    check(vector_cmd_valid, "vector command disappeared before ready");
    tick();
    complete_command(EXEC_TARGET_VECTOR, 16'h0030, CMD_OP_VECTOR_ADD, ERR_NONE);

    phase = 8'h40;
    reset_dut();
    policy = SCHED_PRIORITY_FIRST;
    push_command(CMD_OP_VECTOR_ADD, 3'd1, 16'h0041);
    push_command(CMD_OP_GEMM, 3'd7, 16'h0042);
    execution_enable = 1'b1;
    #1;
    check(gemm_cmd_valid, "priority scheduler did not choose GEMM command first");
    tick();
    complete_command(EXEC_TARGET_GEMM, 16'h0042, CMD_OP_GEMM, ERR_NONE);
    #1;
    check(vector_cmd_valid, "lower-priority vector command did not dispatch second");
    tick();
    complete_command(EXEC_TARGET_VECTOR, 16'h0041, CMD_OP_VECTOR_ADD, ERR_NONE);

    phase = 8'h50;
    reset_dut();
    execution_enable = 1'b0;
    for (index = 0; index < 8; index = index + 1) begin
      push_command(CMD_OP_DMA_COPY, index[2:0], 16'h0500 + index[15:0]);
    end
    check(queue_full && queue_occupancy == 4'd8 && queue_high_water == 4'd8,
          "queue did not report full/high-water edge case");
    push_valid = 1'b1;
    push_opcode = CMD_OP_DMA_COPY;
    #1;
    check(!push_ready, "full queue accepted another command");
    push_valid = 1'b0;

    phase = 8'hff;
    repeat (4) tick();
    $display("PASS artifact_command_tb dispatch invalid backpressure priority full");
    $fclose(trace_fd);
    $finish;
  end
endmodule
