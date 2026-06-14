#include <array>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>

#include "Vservices_test_top.h"
#include "soc_registers.hpp"
#include "verilated.h"

namespace {

constexpr unsigned kMaximumWaitCycles = 64U;
constexpr unsigned kPeriodicInterval = 3U;
constexpr unsigned kPeriodicObservationCycles = 9U;
constexpr unsigned kOneShotInterval = 2U;
constexpr unsigned kInterruptLatencyWaitCycles = 3U;
constexpr unsigned kExpectedInterruptLatency =
    kInterruptLatencyWaitCycles - 1U;
constexpr unsigned kShortObservationCycles = 3U;
constexpr unsigned kTimerInterruptInterval = 2U;
constexpr unsigned kCounterStimulusCycles = 5U;
constexpr unsigned kCounterSaturationCycles = 300U;
constexpr std::uint32_t kCounterMaximum = 0xFFU;

constexpr std::uint32_t bit(unsigned index) {
  return std::uint32_t{1} << index;
}

void expect(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

class Fixture {
 public:
  Fixture() : dut_(&context_) {
    clear_inputs();
    reset();
  }

  ~Fixture() { dut_.final(); }

  Vservices_test_top& dut() { return dut_; }

  void evaluate() { dut_.eval(); }

  void tick() {
    dut_.clk = 0;
    dut_.eval();
    context_.timeInc(1);
    dut_.clk = 1;
    dut_.eval();
    context_.timeInc(1);
    dut_.clk = 0;
    dut_.eval();
    context_.timeInc(1);
  }

  void reset() {
    dut_.rst_n = 0;
    tick();
    tick();
    dut_.rst_n = 1;
    evaluate();
  }

  void clear_interrupts() {
    dut_.irq_sources = 0U;
    dut_.irq_enable = 0U;
    dut_.irq_clear = 0U;
    dut_.timer_enable = 0;
    tick();
    dut_.irq_clear = static_cast<std::uint32_t>(
        (std::uint32_t{1} << soc::IRQ_SOURCE_COUNT) - 1U);
    tick();
    dut_.irq_clear = 0U;
  }

  void clear_performance_counters() {
    clear_performance_inputs();
    dut_.perf_clear = 1;
    tick();
    dut_.perf_clear = 0;
  }

  std::uint32_t read_counter(std::uint32_t counter_id) {
    dut_.perf_select = counter_id;
    evaluate();
    return dut_.perf_value;
  }

  void clear_performance_inputs() {
    dut_.dma_active = 0;
    dut_.dma_stalled = 0;
    dut_.accel_active = 0;
    dut_.accel_stalled = 0;
    dut_.queue_occupancy = 0U;
    dut_.command_completed = 0;
    dut_.bytes_read = 0U;
    dut_.bytes_written = 0U;
    dut_.perf_irq_latency_valid = 0;
    dut_.perf_irq_latency_cycles = 0U;
    dut_.scheduler_stalled = 0;
  }

 private:
  void clear_inputs() {
    dut_.clk = 0;
    dut_.rst_n = 0;
    dut_.timer_enable = 0;
    dut_.timer_periodic = 0;
    dut_.timer_interval = 0U;
    dut_.irq_sources = 0U;
    dut_.irq_enable = 0U;
    dut_.irq_clear = 0U;
    dut_.perf_clear = 0;
    clear_performance_inputs();
    dut_.perf_select = soc::PERF_TOTAL_CYCLES;
  }

  VerilatedContext context_;
  Vservices_test_top dut_;
};

void test_timer(Fixture& fixture) {
  auto& dut = fixture.dut();
  dut.timer_enable = 1;
  dut.timer_periodic = 1;
  dut.timer_interval = kPeriodicInterval;
  fixture.tick();
  expect(dut.timer_active && !dut.timer_tick && dut.timer_value == 0U,
         "periodic timer did not arm from a configuration change");

  unsigned tick_count = 0U;
  for (unsigned cycle = 0; cycle < kPeriodicObservationCycles; ++cycle) {
    fixture.tick();
    if (dut.timer_tick) {
      ++tick_count;
      expect(dut.timer_value == 0U,
             "periodic timer did not restart at zero");
    }
  }
  expect(tick_count ==
             kPeriodicObservationCycles / kPeriodicInterval,
         "periodic timer tick count is incorrect");

  dut.timer_interval = 1U;
  fixture.tick();
  expect(!dut.timer_tick && dut.timer_value == 0U,
         "timer configuration change did not restart the count");
  for (unsigned cycle = 0; cycle < kShortObservationCycles; ++cycle) {
    fixture.tick();
    expect(dut.timer_tick,
           "interval-one periodic timer did not tick every cycle");
  }

  dut.timer_periodic = 0;
  dut.timer_interval = kOneShotInterval;
  fixture.tick();
  expect(dut.timer_active && !dut.timer_tick,
         "one-shot timer did not arm");
  fixture.tick();
  expect(!dut.timer_tick && dut.timer_value == 1U,
         "one-shot timer count is incorrect");
  fixture.tick();
  expect(dut.timer_tick && !dut.timer_active,
         "one-shot timer did not expire exactly once");
  for (unsigned cycle = 0; cycle < kShortObservationCycles; ++cycle) {
    fixture.tick();
    expect(!dut.timer_tick && !dut.timer_active,
           "one-shot timer retriggered without reconfiguration");
  }

  dut.timer_enable = 0;
  fixture.tick();
  expect(!dut.timer_active && !dut.timer_tick && dut.timer_value == 0U,
         "disabled timer did not clear its control state");

  dut.timer_enable = 1;
  dut.timer_interval = 0U;
  fixture.tick();
  for (unsigned cycle = 0; cycle < kShortObservationCycles; ++cycle) {
    fixture.tick();
    expect(!dut.timer_active && !dut.timer_tick,
           "zero-interval timer generated an event");
  }
  dut.timer_enable = 0;
  fixture.tick();
}

void test_interrupt_controller(Fixture& fixture) {
  auto& dut = fixture.dut();
  fixture.clear_interrupts();

  dut.irq_sources = bit(soc::IRQ_DMA_DONE_BIT);
  fixture.tick();
  dut.irq_sources = 0U;
  expect((dut.irq_pending & bit(soc::IRQ_DMA_DONE_BIT)) != 0U &&
             !dut.irq,
         "disabled interrupt source did not become pending cleanly");
  fixture.tick();
  expect((dut.irq_pending & bit(soc::IRQ_DMA_DONE_BIT)) != 0U,
         "pending interrupt did not persist");

  dut.irq_enable = bit(soc::IRQ_DMA_DONE_BIT);
  fixture.evaluate();
  expect(dut.irq, "enabled pending interrupt did not assert IRQ");
  dut.irq_enable = 0U;
  fixture.evaluate();
  expect(!dut.irq &&
             (dut.irq_pending & bit(soc::IRQ_DMA_DONE_BIT)) != 0U,
         "disabling an interrupt removed pending state or left IRQ asserted");
  dut.irq_enable = bit(soc::IRQ_DMA_DONE_BIT);
  fixture.evaluate();
  for (unsigned cycle = 0; cycle < kInterruptLatencyWaitCycles; ++cycle) {
    fixture.tick();
  }
  dut.irq_clear = bit(soc::IRQ_DMA_DONE_BIT);
  fixture.tick();
  dut.irq_clear = 0U;
  expect(!dut.irq &&
             (dut.irq_pending & bit(soc::IRQ_DMA_DONE_BIT)) == 0U,
         "interrupt clear did not remove the pending source");
  expect(dut.irq_latency_valid &&
             dut.irq_latency_cycles == kExpectedInterruptLatency,
         "interrupt service latency is incorrect");

  dut.irq_sources = bit(soc::IRQ_CMD_DONE_BIT);
  dut.irq_clear = bit(soc::IRQ_CMD_DONE_BIT);
  dut.irq_enable = bit(soc::IRQ_CMD_DONE_BIT);
  fixture.tick();
  dut.irq_sources = 0U;
  dut.irq_clear = 0U;
  expect((dut.irq_pending & bit(soc::IRQ_CMD_DONE_BIT)) != 0U &&
             dut.irq,
         "interrupt source did not win over a simultaneous clear");
  dut.irq_clear = bit(soc::IRQ_CMD_DONE_BIT);
  fixture.tick();
  dut.irq_clear = 0U;

  dut.irq_enable = bit(soc::IRQ_ACCEL_DONE_BIT) |
                   bit(soc::IRQ_ERROR_BIT);
  dut.irq_sources = bit(soc::IRQ_ACCEL_DONE_BIT) |
                    bit(soc::IRQ_ERROR_BIT);
  fixture.tick();
  dut.irq_sources = 0U;
  expect(dut.irq &&
             (dut.irq_pending & dut.irq_enable) == dut.irq_enable,
         "simultaneous interrupt sources were not retained");
  dut.irq_clear = bit(soc::IRQ_ACCEL_DONE_BIT);
  fixture.tick();
  dut.irq_clear = 0U;
  expect(dut.irq &&
             (dut.irq_pending & bit(soc::IRQ_ERROR_BIT)) != 0U,
         "selective clear removed another interrupt source");
  dut.irq_clear = bit(soc::IRQ_ERROR_BIT);
  fixture.tick();
  dut.irq_clear = 0U;
  expect(!dut.irq, "final interrupt clear did not deassert IRQ");
}

void test_timer_interrupt(Fixture& fixture) {
  auto& dut = fixture.dut();
  fixture.clear_interrupts();
  dut.irq_enable = bit(soc::IRQ_TIMER_BIT);
  dut.timer_periodic = 1;
  dut.timer_interval = kTimerInterruptInterval;
  dut.timer_enable = 1;

  bool observed = false;
  for (unsigned cycle = 0; cycle < kMaximumWaitCycles; ++cycle) {
    fixture.tick();
    if ((dut.irq_pending & bit(soc::IRQ_TIMER_BIT)) != 0U) {
      observed = true;
      break;
    }
  }
  expect(observed && dut.irq,
         "timer tick did not reach the interrupt controller");

  dut.timer_enable = 0;
  dut.irq_clear = bit(soc::IRQ_TIMER_BIT);
  fixture.tick();
  dut.irq_clear = 0U;
  expect(!dut.irq &&
             (dut.irq_pending & bit(soc::IRQ_TIMER_BIT)) == 0U,
         "timer interrupt did not clear");
}

void test_performance_counters(Fixture& fixture) {
  auto& dut = fixture.dut();
  fixture.clear_performance_counters();

  constexpr std::array<unsigned, kCounterStimulusCycles> kQueue = {
      1U, 5U, 3U, 7U, 2U};
  constexpr std::array<unsigned, kCounterStimulusCycles> kRead = {
      4U, 0U, 3U, 0U, 0U};
  constexpr std::array<unsigned, kCounterStimulusCycles> kWritten = {
      0U, 2U, 0U, 5U, 0U};

  for (unsigned cycle = 0; cycle < kCounterStimulusCycles; ++cycle) {
    dut.dma_active = 1;
    dut.dma_stalled = cycle < 2U;
    dut.accel_active = (cycle % 2U) == 0U;
    dut.accel_stalled = cycle == 1U;
    dut.queue_occupancy = kQueue[cycle];
    dut.command_completed =
        (cycle == 0U) || (cycle == kCounterStimulusCycles - 1U);
    dut.bytes_read = kRead[cycle];
    dut.bytes_written = kWritten[cycle];
    dut.perf_irq_latency_valid = (cycle == 0U) || (cycle == 3U);
    dut.perf_irq_latency_cycles = cycle == 0U ? 4U : 9U;
    dut.scheduler_stalled =
        (cycle == 1U) || (cycle == 2U) || (cycle == 4U);
    fixture.tick();
  }
  fixture.clear_performance_inputs();

  expect(fixture.read_counter(soc::PERF_TOTAL_CYCLES) == 5U,
         "total-cycle counter is incorrect");
  expect(fixture.read_counter(soc::PERF_DMA_ACTIVE_CYCLES) == 5U,
         "DMA-active counter is incorrect");
  expect(fixture.read_counter(soc::PERF_DMA_STALLED_CYCLES) == 2U,
         "DMA-stalled counter is incorrect");
  expect(fixture.read_counter(soc::PERF_ACCEL_ACTIVE_CYCLES) == 3U,
         "accelerator-active counter is incorrect");
  expect(fixture.read_counter(soc::PERF_ACCEL_STALLED_CYCLES) == 1U,
         "accelerator-stalled counter is incorrect");
  expect(fixture.read_counter(soc::PERF_QUEUE_HIGH_WATER) == 7U,
         "queue high-water counter is incorrect");
  expect(fixture.read_counter(soc::PERF_COMMANDS_COMPLETED) == 2U,
         "command completion counter is incorrect");
  expect(fixture.read_counter(soc::PERF_BYTES_READ) == 7U,
         "bytes-read counter is incorrect");
  expect(fixture.read_counter(soc::PERF_BYTES_WRITTEN) == 7U,
         "bytes-written counter is incorrect");
  expect(fixture.read_counter(soc::PERF_IRQ_LATENCY) == 9U,
         "interrupt-latency maximum is incorrect");
  expect(fixture.read_counter(soc::PERF_SCHEDULER_STALLS) == 3U,
         "scheduler-stall counter is incorrect");
  expect(fixture.read_counter(soc::PERF_COUNTER_INVALID) == 0U,
         "reserved performance counter is not zero");

  fixture.clear_performance_counters();
  expect(fixture.read_counter(soc::PERF_TOTAL_CYCLES) == 0U &&
             fixture.read_counter(soc::PERF_BYTES_READ) == 0U &&
             fixture.read_counter(soc::PERF_QUEUE_HIGH_WATER) == 0U,
         "performance counter clear did not reset all counter classes");

  for (unsigned cycle = 0; cycle < kCounterSaturationCycles; ++cycle) {
    fixture.tick();
  }
  expect(fixture.read_counter(soc::PERF_TOTAL_CYCLES) ==
             kCounterMaximum,
         "total-cycle counter did not saturate");

  dut.bytes_read = 250U;
  fixture.tick();
  dut.bytes_read = 10U;
  fixture.tick();
  dut.bytes_read = 0U;
  expect(fixture.read_counter(soc::PERF_BYTES_READ) == kCounterMaximum,
         "bytes-read counter did not saturate");
}

void run_directed(Fixture& fixture) {
  test_timer(fixture);
  test_interrupt_controller(fixture);
  test_timer_interrupt(fixture);
  test_performance_counters(fixture);
  fixture.reset();
  expect(!fixture.dut().timer_active && !fixture.dut().timer_tick &&
             fixture.dut().irq_pending == 0U && !fixture.dut().irq &&
             fixture.read_counter(soc::PERF_TOTAL_CYCLES) == 0U,
         "service reset state is incorrect");
}

}  // namespace

int main(int argc, char** argv) {
  std::string test_name = "smoke";
  std::uint32_t seed = 1U;

  for (int index = 1; index < argc; ++index) {
    const std::string argument = argv[index];
    if ((argument == "--test") && (index + 1 < argc)) {
      test_name = argv[++index];
    } else if ((argument == "--seed") && (index + 1 < argc)) {
      seed = static_cast<std::uint32_t>(std::stoul(argv[++index]));
    } else if (argument != "--coverage") {
      std::cerr << "error: unknown argument: " << argument << '\n';
      return 2;
    }
  }

  try {
    Fixture fixture;
    run_directed(fixture);
    if ((test_name != "smoke") && (test_name != "regress")) {
      throw std::runtime_error("unsupported test name: " + test_name);
    }
    std::cout << "PASS test=" << test_name << " seed=" << seed << '\n';
  } catch (const std::exception& error) {
    std::cerr << "FAIL test=" << test_name << " seed=" << seed
              << " reason=" << error.what() << '\n';
    return 1;
  }

  return 0;
}
