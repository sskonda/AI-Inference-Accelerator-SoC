`timescale 1ns/1ps

module artifact_services_tb;
  import soc_pkg::*;
  import reg_pkg::*;

  logic clk;
  logic rst_n;

  logic timer_enable;
  logic timer_periodic;
  logic [7:0] timer_interval;
  logic [7:0] timer_value;
  logic timer_tick;
  logic timer_active;

  logic [IRQ_SOURCE_COUNT-1:0] irq_sources;
  logic [IRQ_SOURCE_COUNT-1:0] irq_enable;
  logic [IRQ_SOURCE_COUNT-1:0] irq_clear;
  logic [IRQ_SOURCE_COUNT-1:0] irq_pending;
  logic irq;
  logic irq_latency_valid;
  logic [7:0] irq_latency_cycles;

  logic perf_clear;
  logic dma_active;
  logic dma_stalled;
  logic accel_active;
  logic accel_stalled;
  logic [QUEUE_OCCUPANCY_WIDTH-1:0] queue_occupancy;
  logic command_completed;
  logic [BYTE_COUNT_WIDTH-1:0] bytes_read;
  logic [BYTE_COUNT_WIDTH-1:0] bytes_written;
  logic perf_irq_latency_valid;
  logic [7:0] perf_irq_latency_cycles;
  logic scheduler_stalled;
  logic [PERF_COUNTER_ID_WIDTH-1:0] perf_select;
  logic [7:0] perf_value;
  logic [DATA_WIDTH-1:0] definition_checksum;

  logic [7:0] phase;
  integer trace_fd;
  integer tick_count;

  services_test_top dut (
      .clk(clk),
      .rst_n(rst_n),
      .timer_enable(timer_enable),
      .timer_periodic(timer_periodic),
      .timer_interval(timer_interval),
      .timer_value(timer_value),
      .timer_tick(timer_tick),
      .timer_active(timer_active),
      .irq_sources(irq_sources),
      .irq_enable(irq_enable),
      .irq_clear(irq_clear),
      .irq_pending(irq_pending),
      .irq(irq),
      .irq_latency_valid(irq_latency_valid),
      .irq_latency_cycles(irq_latency_cycles),
      .perf_clear(perf_clear),
      .dma_active(dma_active),
      .dma_stalled(dma_stalled),
      .accel_active(accel_active),
      .accel_stalled(accel_stalled),
      .queue_occupancy(queue_occupancy),
      .command_completed(command_completed),
      .bytes_read(bytes_read),
      .bytes_written(bytes_written),
      .perf_irq_latency_valid(perf_irq_latency_valid),
      .perf_irq_latency_cycles(perf_irq_latency_cycles),
      .scheduler_stalled(scheduler_stalled),
      .perf_select(perf_select),
      .perf_value(perf_value),
      .definition_checksum(definition_checksum)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic check(input logic condition, input string message);
    if (!condition) begin
      $display("FAIL services: %s at %0t", message, $time);
      $fatal(1);
    end
  endtask

  task automatic tick;
    @(posedge clk);
    #1;
  endtask

  task automatic clear_inputs;
    begin
      timer_enable = 1'b0;
      timer_periodic = 1'b0;
      timer_interval = '0;
      irq_sources = '0;
      irq_enable = '0;
      irq_clear = '0;
      perf_clear = 1'b0;
      dma_active = 1'b0;
      dma_stalled = 1'b0;
      accel_active = 1'b0;
      accel_stalled = 1'b0;
      queue_occupancy = '0;
      command_completed = 1'b0;
      bytes_read = '0;
      bytes_written = '0;
      perf_irq_latency_valid = 1'b0;
      perf_irq_latency_cycles = '0;
      scheduler_stalled = 1'b0;
      perf_select = PERF_TOTAL_CYCLES;
      tick_count = 0;
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

  always @(posedge clk) begin
    if (rst_n && timer_tick) begin
      tick_count <= tick_count + 1;
    end
  end

  always @(posedge clk) begin
    if (trace_fd != 0) begin
      $fdisplay(
          trace_fd,
          "%0t,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0b,%0b,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
          $time,
          phase,
          rst_n,
          timer_enable,
          timer_periodic,
          timer_interval,
          timer_value,
          timer_tick,
          timer_active,
          irq_sources,
          irq_pending,
          irq,
          irq_latency_valid,
          irq_latency_cycles,
          dma_active,
          dma_stalled,
          accel_active,
          command_completed,
          scheduler_stalled,
          perf_value
      );
    end
  end

  initial begin
    trace_fd = $fopen("Images/traces/services_trace.csv", "w");
    $fdisplay(trace_fd, "time,phase,rst_n,timer_enable,timer_periodic,timer_interval,timer_value,timer_tick,timer_active,irq_sources,irq_pending,irq,irq_latency_valid,irq_latency_cycles,dma_active,dma_stalled,accel_active,command_completed,scheduler_stalled,perf_value");

    phase = 8'h01;
    reset_dut();
    check(!timer_active && !irq && irq_pending == '0, "reset state incorrect");

    phase = 8'h10;
    tick_count = 0;
    timer_enable = 1'b1;
    timer_periodic = 1'b0;
    timer_interval = 8'd3;
    repeat (6) tick();
    check(tick_count == 1, "one-shot timer did not tick exactly once");
    check(!timer_active, "one-shot timer remained active after expiration");

    phase = 8'h20;
    tick_count = 0;
    timer_periodic = 1'b1;
    timer_interval = 8'd2;
    repeat (7) tick();
    check(tick_count >= 2, "periodic timer did not retrigger");
    check(timer_active, "periodic timer de-armed unexpectedly");

    phase = 8'h30;
    irq_enable = '0;
    irq_enable[IRQ_DMA_DONE_BIT] = 1'b1;
    irq_sources[IRQ_DMA_DONE_BIT] = 1'b1;
    tick();
    irq_sources[IRQ_DMA_DONE_BIT] = 1'b0;
    tick();
    check(irq_pending[IRQ_DMA_DONE_BIT] && irq, "enabled IRQ did not assert");
    repeat (3) tick();
    irq_clear[IRQ_DMA_DONE_BIT] = 1'b1;
    tick();
    irq_clear[IRQ_DMA_DONE_BIT] = 1'b0;
    check(irq_latency_valid, "IRQ clear did not report service latency");
    tick();
    check(!irq_pending[IRQ_DMA_DONE_BIT] && !irq, "IRQ did not clear");

    phase = 8'h40;
    perf_clear = 1'b1;
    tick();
    perf_clear = 1'b0;
    dma_active = 1'b1;
    dma_stalled = 1'b1;
    accel_active = 1'b1;
    queue_occupancy = 8'd5;
    command_completed = 1'b1;
    bytes_read = 24'd12;
    bytes_written = 24'd8;
    scheduler_stalled = 1'b1;
    repeat (3) tick();
    dma_active = 1'b0;
    dma_stalled = 1'b0;
    accel_active = 1'b0;
    command_completed = 1'b0;
    bytes_read = '0;
    bytes_written = '0;
    scheduler_stalled = 1'b0;
    perf_select = PERF_DMA_ACTIVE_CYCLES;
    #1;
    check(perf_value == 8'd3, "DMA active counter mismatch");
    perf_select = PERF_DMA_STALLED_CYCLES;
    #1;
    check(perf_value == 8'd3, "DMA stalled counter mismatch");
    perf_select = PERF_QUEUE_HIGH_WATER;
    #1;
    check(perf_value == 8'd5, "queue high-water counter mismatch");
    perf_select = PERF_COMMANDS_COMPLETED;
    #1;
    check(perf_value == 8'd3, "command completed counter mismatch");
    perf_select = PERF_BYTES_READ;
    #1;
    check(perf_value == 8'd36, "bytes-read counter mismatch");
    perf_select = PERF_BYTES_WRITTEN;
    #1;
    check(perf_value == 8'd24, "bytes-written counter mismatch");
    perf_select = PERF_SCHEDULER_STALLS;
    #1;
    check(perf_value == 8'd3, "scheduler stall counter mismatch");
    perf_clear = 1'b1;
    tick();
    perf_clear = 1'b0;
    perf_select = PERF_DMA_ACTIVE_CYCLES;
    #1;
    check(perf_value == 8'd0, "performance clear failed");

    phase = 8'hff;
    repeat (4) tick();
    $display("PASS artifact_services_tb timer irq perf_counters clear");
    $fclose(trace_fd);
    $finish;
  end
endmodule
