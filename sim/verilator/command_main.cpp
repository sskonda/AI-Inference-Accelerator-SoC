#include <array>
#include <cstdint>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#include "Vcommand_test_top.h"
#include "sim_utils.hpp"
#include "soc_registers.hpp"
#include "verilated.h"

namespace {

constexpr unsigned kQueueDepth = 8U;
constexpr unsigned kMaximumWaitCycles = 64U;
constexpr unsigned kRandomCommandCount = 200U;
constexpr unsigned kDisabledStarvationThreshold = 0U;
constexpr unsigned kStarvationThreshold = 6U;
constexpr std::uint32_t kSourceZeroBase = 0x10000100U;
constexpr std::uint32_t kSourceOneBase = 0x10000200U;
constexpr std::uint32_t kDestinationBase = 0x10000300U;
constexpr std::uint32_t kCompletionResultBase = 0xCAFE0000U;
constexpr std::uint32_t kMaximumPriority = 7U;
constexpr std::uint32_t kDefaultLength = 16U;
constexpr std::uint32_t kDefaultDimension = 2U;

struct Command {
  std::uint32_t opcode;
  std::uint32_t command_id;
  std::uint32_t priority;
};

void expect(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

std::uint32_t target_for_opcode(std::uint32_t opcode) {
  if (opcode == soc::CMD_OP_DMA_COPY) {
    return soc::EXEC_TARGET_DMA;
  }
  if (opcode >= soc::CMD_OP_VECTOR_ADD &&
      opcode <= soc::CMD_OP_VECTOR_CLAMP) {
    return soc::EXEC_TARGET_VECTOR;
  }
  if (opcode == soc::CMD_OP_REDUCE_SUM ||
      opcode == soc::CMD_OP_REDUCE_MAX) {
    return soc::EXEC_TARGET_REDUCTION;
  }
  if (opcode == soc::CMD_OP_GEMM) {
    return soc::EXEC_TARGET_GEMM;
  }
  return soc::EXEC_TARGET_INVALID;
}

class Fixture {
 public:
  Fixture() : dut_(&context_) {
    clear_inputs();
    reset();
  }

  ~Fixture() { dut_.final(); }

  Vcommand_test_top& dut() { return dut_; }

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

  void set_command(const Command& command) {
    dut_.push_opcode = command.opcode;
    dut_.push_src0_addr = kSourceZeroBase + command.command_id;
    dut_.push_src1_addr = kSourceOneBase + command.command_id;
    dut_.push_dst_addr = kDestinationBase + command.command_id;
    dut_.push_length = kDefaultLength;
    dut_.push_m = kDefaultDimension;
    dut_.push_n = kDefaultDimension;
    dut_.push_k = kDefaultDimension;
    dut_.push_flags = 0U;
    dut_.push_priority = command.priority;
    dut_.push_command_id = command.command_id;
  }

  void push(const Command& command) {
    set_command(command);
    dut_.push_valid = 1;
    evaluate();
    expect(dut_.push_ready, "Command queue rejected a legal enqueue");
    tick();
    dut_.push_valid = 0;
    evaluate();
  }

  std::uint32_t visible_dispatch_target() {
    const std::array<std::uint32_t, 4> valid = {
        dut_.dma_cmd_valid, dut_.vector_cmd_valid,
        dut_.reduction_cmd_valid, dut_.gemm_cmd_valid};
    const std::array<std::uint32_t, 4> targets = {
        soc::EXEC_TARGET_DMA, soc::EXEC_TARGET_VECTOR,
        soc::EXEC_TARGET_REDUCTION, soc::EXEC_TARGET_GEMM};

    std::uint32_t target = soc::EXEC_TARGET_INVALID;
    unsigned valid_count = 0U;
    for (std::size_t index = 0; index < valid.size(); ++index) {
      if (valid[index] != 0U) {
        target = targets[index];
        ++valid_count;
      }
    }
    expect(valid_count <= 1U, "Command processor asserted multiple dispatch ports");
    return target;
  }

  void set_backend_ready(bool ready) {
    dut_.dma_cmd_ready = ready;
    dut_.vector_cmd_ready = ready;
    dut_.reduction_cmd_ready = ready;
    dut_.gemm_cmd_ready = ready;
  }

  void dispatch_and_complete(
      const Command& expected,
      std::uint32_t completion_error = soc::ERR_NONE,
      bool stall_response = false) {
    set_backend_ready(true);
    dut_.execution_enable = 1;

    std::uint32_t target = soc::EXEC_TARGET_INVALID;
    for (unsigned cycle = 0; cycle < kMaximumWaitCycles; ++cycle) {
      evaluate();
      target = visible_dispatch_target();
      if (target != soc::EXEC_TARGET_INVALID) {
        break;
      }
      tick();
    }

    expect(target == target_for_opcode(expected.opcode),
           "Command dispatched to the wrong executor");
    expect(dut_.dispatch_opcode == expected.opcode &&
               dut_.dispatch_command_id == expected.command_id &&
               dut_.dispatch_priority == expected.priority,
           "Dispatched command payload is incorrect");

    tick();
    expect(dut_.processor_busy, "Processor did not enter its active state");

    dut_.completion_target = target;
    dut_.completion_command_id = expected.command_id;
    dut_.completion_opcode = expected.opcode;
    dut_.completion_error = completion_error;
    dut_.completion_result = kCompletionResultBase + expected.command_id;
    dut_.completion_valid = 1;
    evaluate();
    expect(dut_.completion_ready, "Processor did not accept executor completion");
    tick();
    dut_.completion_valid = 0;

    expect(dut_.response_valid && dut_.command_completed,
           "Processor did not publish command completion");
    expect(dut_.response_command_id == expected.command_id &&
               dut_.response_opcode == expected.opcode &&
               dut_.response_error == completion_error &&
               dut_.response_result ==
                   kCompletionResultBase + expected.command_id &&
               dut_.response_cycles != 0U,
           "Command response payload is incorrect");
    expect(dut_.command_error == (completion_error != soc::ERR_NONE),
           "Command error event does not match completion status");

    if (stall_response) {
      const auto held_cycles = dut_.response_cycles;
      const auto held_result = dut_.response_result;
      tick();
      expect(dut_.response_valid && dut_.response_cycles == held_cycles &&
                 dut_.response_result == held_result,
             "Command response changed under backpressure");
    }

    dut_.response_ready = 1;
    tick();
    dut_.response_ready = 0;
    evaluate();
    expect(!dut_.response_valid && !dut_.processor_busy,
           "Processor did not retire the consumed response");
  }

  void process_invalid(const Command& command) {
    dut_.execution_enable = 1;
    evaluate();
    expect(visible_dispatch_target() == soc::EXEC_TARGET_INVALID,
           "Invalid opcode reached an executor");
    tick();
    expect(dut_.response_valid && dut_.command_completed &&
               dut_.command_error &&
               dut_.response_command_id == command.command_id &&
               dut_.response_opcode == command.opcode &&
               dut_.response_error == soc::ERR_OPCODE,
           "Invalid opcode did not produce a tagged error response");
    dut_.response_ready = 1;
    tick();
    dut_.response_ready = 0;
  }

 private:
  void clear_inputs() {
    dut_.clk = 0;
    dut_.rst_n = 0;
    dut_.execution_enable = 0;
    dut_.push_valid = 0;
    set_command({soc::CMD_OP_INVALID, 0U, 0U});
    dut_.policy = soc::SCHED_ROUND_ROBIN;
    dut_.starvation_threshold = kDisabledStarvationThreshold;
    set_backend_ready(false);
    dut_.completion_valid = 0;
    dut_.completion_target = soc::EXEC_TARGET_INVALID;
    dut_.completion_command_id = 0U;
    dut_.completion_opcode = soc::CMD_OP_INVALID;
    dut_.completion_error = soc::ERR_NONE;
    dut_.completion_result = 0U;
    dut_.response_ready = 0;
  }

  VerilatedContext context_;
  Vcommand_test_top dut_;
};

void test_empty_full_and_reset(Fixture& fixture) {
  auto& dut = fixture.dut();
  expect(dut.queue_empty && !dut.queue_full && dut.queue_occupancy == 0U,
         "Command queue reset state is incorrect");

  dut.execution_enable = 0;
  for (unsigned index = 0; index < kQueueDepth; ++index) {
    fixture.push({soc::CMD_OP_VECTOR_ADD, index + 1U, index});
  }
  expect(dut.queue_full && !dut.queue_empty &&
             dut.queue_occupancy == kQueueDepth &&
             dut.queue_high_water == kQueueDepth,
         "Command queue did not report full occupancy");

  fixture.set_command({soc::CMD_OP_GEMM, 0xFFU, kMaximumPriority});
  dut.push_valid = 1;
  fixture.evaluate();
  expect(!dut.push_ready, "Command queue accepted an enqueue while full");
  dut.push_valid = 0;

  fixture.reset();
  expect(dut.queue_empty && !dut.queue_full && dut.queue_occupancy == 0U &&
             dut.queue_high_water == 0U,
         "Reset did not clear a nonempty command queue");
}

void test_single_and_backpressure(Fixture& fixture) {
  auto& dut = fixture.dut();
  const Command command = {soc::CMD_OP_VECTOR_ADD, 0x101U, 3U};
  dut.execution_enable = 0;
  fixture.push(command);
  dut.vector_cmd_ready = 0;
  dut.execution_enable = 1;
  fixture.evaluate();

  expect(dut.vector_cmd_valid && dut.scheduler_stalled,
         "Unavailable executor did not stall the scheduler");
  const auto held_id = dut.dispatch_command_id;
  const auto held_opcode = dut.dispatch_opcode;
  fixture.tick();
  expect(dut.vector_cmd_valid && dut.dispatch_command_id == held_id &&
             dut.dispatch_opcode == held_opcode,
         "Dispatch payload changed while executor was stalled");

  dut.vector_cmd_ready = 1;
  fixture.dispatch_and_complete(command, soc::ERR_NONE, true);
  expect(dut.queue_empty, "Single command did not leave the queue empty");
}

void test_round_robin_and_back_to_back(Fixture& fixture) {
  auto& dut = fixture.dut();
  fixture.reset();
  dut.policy = soc::SCHED_ROUND_ROBIN;
  dut.starvation_threshold = kDisabledStarvationThreshold;
  dut.execution_enable = 0;

  const std::vector<Command> commands = {
      {soc::CMD_OP_DMA_COPY, 0x201U, 1U},
      {soc::CMD_OP_VECTOR_SCALE, 0x202U, 7U},
      {soc::CMD_OP_REDUCE_SUM, 0x203U, 4U},
      {soc::CMD_OP_GEMM, 0x204U, 2U},
  };
  for (const auto& command : commands) {
    fixture.push(command);
  }
  for (const auto& command : commands) {
    fixture.dispatch_and_complete(command);
  }
  expect(dut.queue_empty && dut.queue_occupancy == 0U,
         "Round-robin sequence dropped a command");
}

void test_priority_policy(Fixture& fixture) {
  auto& dut = fixture.dut();
  fixture.reset();
  dut.policy = soc::SCHED_PRIORITY_FIRST;
  dut.starvation_threshold = kDisabledStarvationThreshold;
  dut.execution_enable = 0;

  const Command low = {soc::CMD_OP_VECTOR_RELU, 0x301U, 1U};
  const Command medium = {soc::CMD_OP_VECTOR_RELU, 0x302U, 4U};
  const Command high = {soc::CMD_OP_VECTOR_RELU, 0x303U, 7U};
  fixture.push(low);
  fixture.push(medium);
  fixture.push(high);

  fixture.dispatch_and_complete(high);
  fixture.dispatch_and_complete(medium);
  fixture.dispatch_and_complete(low);
  expect(dut.queue_empty, "Priority scheduler did not drain the queue");
}

void test_starvation_guard(Fixture& fixture) {
  auto& dut = fixture.dut();
  fixture.reset();
  dut.policy = soc::SCHED_PRIORITY_FIRST;
  dut.starvation_threshold = kStarvationThreshold;
  dut.execution_enable = 0;

  const Command low = {soc::CMD_OP_VECTOR_CLAMP, 0x401U, 0U};
  const std::array<Command, 3> high = {{
      {soc::CMD_OP_VECTOR_CLAMP, 0x402U, kMaximumPriority},
      {soc::CMD_OP_VECTOR_CLAMP, 0x403U, kMaximumPriority},
      {soc::CMD_OP_VECTOR_CLAMP, 0x404U, kMaximumPriority},
  }};
  fixture.push(low);
  for (const auto& command : high) {
    fixture.push(command);
  }

  fixture.dispatch_and_complete(high[0]);
  fixture.dispatch_and_complete(high[1]);
  fixture.evaluate();
  expect(dut.selected_starved,
         "Starvation threshold did not mark the waiting command");
  fixture.dispatch_and_complete(low);
  fixture.dispatch_and_complete(high[2]);
  expect(dut.queue_empty, "Starvation-guard sequence did not drain the queue");
}

void test_invalid_opcode(Fixture& fixture) {
  auto& dut = fixture.dut();
  fixture.reset();
  dut.execution_enable = 0;
  const Command invalid = {soc::CMD_OP_INVALID, 0x501U, 2U};
  fixture.push(invalid);
  fixture.process_invalid(invalid);
  expect(dut.queue_empty, "Invalid command remained in the queue");
}

void test_all_opcode_routes(Fixture& fixture) {
  auto& dut = fixture.dut();
  fixture.reset();
  dut.policy = soc::SCHED_ROUND_ROBIN;
  dut.execution_enable = 0;

  const std::array<std::uint32_t, 9> opcodes = {
      soc::CMD_OP_DMA_COPY,        soc::CMD_OP_VECTOR_ADD,
      soc::CMD_OP_VECTOR_MULTIPLY, soc::CMD_OP_VECTOR_SCALE,
      soc::CMD_OP_VECTOR_RELU,     soc::CMD_OP_VECTOR_CLAMP,
      soc::CMD_OP_REDUCE_SUM,      soc::CMD_OP_REDUCE_MAX,
      soc::CMD_OP_GEMM};

  std::uint32_t command_id = 0x600U;
  for (const auto opcode : opcodes) {
    const Command command = {
        opcode, command_id++, opcode % (kMaximumPriority + 1U)};
    fixture.push(command);
    fixture.dispatch_and_complete(command);
  }
}

void test_random_commands(Fixture& fixture, std::mt19937& random) {
  auto& dut = fixture.dut();
  fixture.reset();
  dut.policy = soc::SCHED_ROUND_ROBIN;
  dut.starvation_threshold = kDisabledStarvationThreshold;

  std::uniform_int_distribution<std::uint32_t> opcode_distribution(
      soc::CMD_OP_DMA_COPY, soc::CMD_OP_GEMM);
  std::uniform_int_distribution<std::uint32_t> priority_distribution(
      0U, kMaximumPriority);
  std::uniform_int_distribution<std::uint32_t> error_distribution(0U, 15U);

  for (unsigned index = 0; index < kRandomCommandCount; ++index) {
    dut.execution_enable = 0;
    const Command command = {
        opcode_distribution(random), 0x1000U + index,
        priority_distribution(random)};
    fixture.push(command);
    const auto injected_error =
        error_distribution(random) == 0U ? soc::ERR_INTERNAL : soc::ERR_NONE;
    fixture.dispatch_and_complete(command, injected_error);
  }
  expect(dut.queue_empty && dut.queue_occupancy == 0U,
         "Random command sequence did not retire every command");
}

std::uint32_t parse_seed(int argc, char** argv) {
  std::uint32_t seed = 1U;
  for (int index = 1; index + 1 < argc; ++index) {
    if (std::string(argv[index]) == "--seed") {
      seed = static_cast<std::uint32_t>(std::stoul(argv[index + 1]));
    }
  }
  return seed;
}

}  // namespace

int main(int argc, char** argv) {
  const auto seed = parse_seed(argc, argv);
  Verilated::commandArgs(argc, argv);

  try {
    Fixture fixture;
    std::mt19937 random(seed);
    test_empty_full_and_reset(fixture);
    test_single_and_backpressure(fixture);
    test_round_robin_and_back_to_back(fixture);
    test_priority_policy(fixture);
    test_starvation_guard(fixture);
    test_invalid_opcode(fixture);
    test_all_opcode_routes(fixture);
    test_random_commands(fixture, random);
    sim::write_coverage_if_requested(argc, argv);
    std::cout << "PASS test=command seed=" << seed << '\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL test=command seed=" << seed
              << " reason=" << error.what() << '\n';
    return 1;
  }
}
