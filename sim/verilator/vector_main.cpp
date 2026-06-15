#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <optional>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#include "Vvector_test_top.h"
#include "soc_memory_map.hpp"
#include "soc_registers.hpp"
#include "vector_model.hpp"
#include "verilated.h"

namespace {

constexpr std::uint32_t kSource0Base = soc::SPM_BASE_ADDR + 0x0100U;
constexpr std::uint32_t kSource1Base = soc::SPM_BASE_ADDR + 0x1100U;
constexpr std::uint32_t kDestinationBase = soc::SPM_BASE_ADDR + 0x2100U;
constexpr std::uint32_t kScalarAddress = soc::SPM_BASE_ADDR + 0x3100U;
constexpr std::uint32_t kCommandIdBase = 0x800U;
constexpr std::uint8_t kDestinationSentinel = 0xA5U;
constexpr unsigned kBitsPerByte = 8U;
constexpr unsigned kElementBytes = soc::ELEMENT_WIDTH / kBitsPerByte;
constexpr unsigned kElementsPerWord = soc::DATA_BYTES / kElementBytes;
constexpr unsigned kMaximumCommandCycles = 20000U;
constexpr unsigned kRandomCaseCount = 100U;

void expect(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

struct PortConfig {
  unsigned ready_block_modulus = 0U;
  unsigned ready_block_residue = 0U;
  unsigned response_latency = 0U;
};

struct PendingResponse {
  std::uint32_t data;
  bool error;
  unsigned delay;
};

struct PortState {
  bool response_valid = false;
  std::uint32_t response_data = 0U;
  bool response_error = false;
  std::optional<PendingResponse> pending;
  bool fail_next_request = false;
  std::size_t read_requests = 0U;
  std::size_t write_requests = 0U;
  std::vector<std::uint32_t> write_strobes;
};

struct Command {
  std::uint32_t opcode = soc::CMD_OP_VECTOR_ADD;
  std::uint32_t source0 = kSource0Base;
  std::uint32_t source1 = kSource1Base;
  std::uint32_t destination = kDestinationBase;
  std::uint32_t length = 1U;
  std::uint32_t flags = 0U;
  std::uint32_t command_id = kCommandIdBase;
};

struct CommandResult {
  std::uint32_t error;
  std::uint32_t result;
  std::uint32_t cycles;
  std::uint64_t active_cycles;
  std::uint64_t stalled_cycles;
  std::uint64_t completed_elements;
  std::size_t reads;
  std::size_t writes;
};

class ScratchpadImage {
 public:
  ScratchpadImage() : bytes_(soc::SPM_SIZE_BYTES, 0U) {}

  void fill(std::uint32_t address, std::size_t length, std::uint8_t value) {
    const auto offset = locate(address, length);
    std::fill(bytes_.begin() + static_cast<std::ptrdiff_t>(offset),
              bytes_.begin() + static_cast<std::ptrdiff_t>(offset + length),
              value);
  }

  void write_elements(std::uint32_t address,
                      const std::vector<std::uint16_t>& values) {
    const auto length = values.size() * kElementBytes;
    const auto offset = locate(address, length);
    for (std::size_t index = 0; index < values.size(); ++index) {
      bytes_[offset + index * kElementBytes] =
          static_cast<std::uint8_t>(values[index]);
      bytes_[offset + index * kElementBytes + 1U] =
          static_cast<std::uint8_t>(values[index] >> kBitsPerByte);
    }
  }

  std::vector<std::uint16_t> read_elements(std::uint32_t address,
                                           std::size_t count) const {
    const auto length = count * kElementBytes;
    const auto offset = locate(address, length);
    std::vector<std::uint16_t> values(count);
    for (std::size_t index = 0; index < count; ++index) {
      values[index] = static_cast<std::uint16_t>(
          bytes_[offset + index * kElementBytes] |
          (static_cast<std::uint16_t>(
               bytes_[offset + index * kElementBytes + 1U])
           << kBitsPerByte));
    }
    return values;
  }

  std::vector<std::uint8_t> read_bytes(std::uint32_t address,
                                       std::size_t length) const {
    const auto offset = locate(address, length);
    return std::vector<std::uint8_t>(
        bytes_.begin() + static_cast<std::ptrdiff_t>(offset),
        bytes_.begin() + static_cast<std::ptrdiff_t>(offset + length));
  }

  bool read_word(std::uint32_t address, std::uint32_t& value) const {
    try {
      const auto offset = locate(address, soc::DATA_BYTES);
      value = 0U;
      for (std::size_t byte_index = 0; byte_index < soc::DATA_BYTES;
           ++byte_index) {
        value |= static_cast<std::uint32_t>(bytes_[offset + byte_index])
                 << (byte_index * kBitsPerByte);
      }
      return true;
    } catch (const std::out_of_range&) {
      value = 0U;
      return false;
    }
  }

  bool write_word(std::uint32_t address, std::uint32_t value,
                  std::uint32_t strobe) {
    try {
      const auto offset = locate(address, soc::DATA_BYTES);
      for (std::size_t byte_index = 0; byte_index < soc::DATA_BYTES;
           ++byte_index) {
        if ((strobe & (std::uint32_t{1} << byte_index)) != 0U) {
          bytes_[offset + byte_index] = static_cast<std::uint8_t>(
              value >> (byte_index * kBitsPerByte));
        }
      }
      return true;
    } catch (const std::out_of_range&) {
      return false;
    }
  }

 private:
  std::size_t locate(std::uint32_t address, std::size_t length) const {
    if (address < soc::SPM_BASE_ADDR) {
      throw std::out_of_range("address below scratchpad");
    }
    const auto offset =
        static_cast<std::size_t>(address - soc::SPM_BASE_ADDR);
    if (offset > bytes_.size() || length > bytes_.size() - offset) {
      throw std::out_of_range("range outside scratchpad");
    }
    return offset;
  }

  std::vector<std::uint8_t> bytes_;
};

class Fixture {
 public:
  Fixture() : dut_(&context_) {
    clear_inputs();
    reset();
  }

  ~Fixture() { dut_.final(); }

  Vvector_test_top& dut() { return dut_; }
  ScratchpadImage& memory() { return memory_; }
  const PortState& port_state() const { return port_state_; }

  void configure_port(const PortConfig& config) { port_config_ = config; }

  void fail_next_request() { port_state_.fail_next_request = true; }

  void evaluate() { dut_.eval(); }

  void tick() {
    prepare_response();
    drive_memory_inputs();

    dut_.clk = 0;
    dut_.eval();
    context_.timeInc(1);

    const bool request_fire = dut_.memory_req_valid && dut_.memory_req_ready;
    const bool response_fire = dut_.memory_rsp_valid && dut_.memory_rsp_ready;
    const bool request_write = dut_.memory_req_write;
    const std::uint32_t request_address = dut_.memory_req_addr;
    const std::uint32_t request_data = dut_.memory_req_wdata;
    const std::uint32_t request_strobe = dut_.memory_req_wstrb;

    dut_.clk = 1;
    dut_.eval();
    context_.timeInc(1);

    if (dut_.active_cycle) {
      ++active_cycles_;
    }
    if (dut_.stalled_cycle) {
      ++stalled_cycles_;
    }
    completed_elements_ += dut_.elements_completed_event;

    if (response_fire) {
      consume_response();
    }
    if (request_fire) {
      accept_request(request_write, request_address, request_data,
                     request_strobe);
    }

    dut_.clk = 0;
    dut_.eval();
    context_.timeInc(1);
    ++cycle_;
  }

  void reset() {
    dut_.command_valid = 0;
    dut_.response_ready = 0;
    port_state_ = PortState{};
    active_cycles_ = 0U;
    stalled_cycles_ = 0U;
    completed_elements_ = 0U;
    cycle_ = 0U;
    dut_.rst_n = 0;
    tick();
    tick();
    dut_.rst_n = 1;
    evaluate();
  }

  void start_command(const Command& command) {
    drive_command(command);
    dut_.command_valid = 1;
    evaluate();
    expect(dut_.command_ready, "vector command was not accepted while idle");
    tick();
    dut_.command_valid = 0;
    evaluate();
  }

  CommandResult finish_command(const Command& command,
                               bool hold_response = false) {
    const auto initial_reads = port_state_.read_requests;
    const auto initial_writes = port_state_.write_requests;
    const auto initial_active = active_cycles_;
    const auto initial_stalled = stalled_cycles_;
    const auto initial_completed = completed_elements_;

    bool saw_done = false;
    bool saw_error = false;
    for (unsigned wait_cycle = 0; wait_cycle < kMaximumCommandCycles;
         ++wait_cycle) {
      saw_done = saw_done || dut_.done;
      saw_error = saw_error || dut_.error;
      if (dut_.response_valid) {
        expect(dut_.response_command_id == command.command_id,
               "vector response command ID mismatch");
        expect(dut_.response_opcode == command.opcode,
               "vector response opcode mismatch");
        expect(saw_done, "vector response appeared without done event");
        expect(saw_error == (dut_.response_error != soc::ERR_NONE),
               "vector error event did not match response");

        if (hold_response) {
          const auto held_error = dut_.response_error;
          const auto held_result = dut_.response_result;
          const auto held_cycles = dut_.response_cycles;
          tick();
          tick();
          expect(dut_.response_valid &&
                     dut_.response_error == held_error &&
                     dut_.response_result == held_result &&
                     dut_.response_cycles == held_cycles,
                 "vector response changed under backpressure");
        }

        const CommandResult result = {
            dut_.response_error,
            dut_.response_result,
            dut_.response_cycles,
            active_cycles_ - initial_active,
            stalled_cycles_ - initial_stalled,
            completed_elements_ - initial_completed,
            port_state_.read_requests - initial_reads,
            port_state_.write_requests - initial_writes};
        dut_.response_ready = 1;
        tick();
        dut_.response_ready = 0;
        evaluate();
        expect(!dut_.busy && !dut_.response_valid,
               "vector accelerator did not retire response");
        return result;
      }
      tick();
    }
    throw std::runtime_error("vector command timed out");
  }

  CommandResult run_command(const Command& command,
                            bool hold_response = false) {
    start_command(command);
    return finish_command(command, hold_response);
  }

 private:
  bool request_ready() const {
    if (port_config_.ready_block_modulus == 0U) {
      return true;
    }
    return (cycle_ % port_config_.ready_block_modulus) !=
           port_config_.ready_block_residue;
  }

  void prepare_response() {
    if (port_state_.response_valid || !port_state_.pending.has_value()) {
      return;
    }
    if (port_state_.pending->delay != 0U) {
      --port_state_.pending->delay;
      return;
    }
    port_state_.response_valid = true;
    port_state_.response_data = port_state_.pending->data;
    port_state_.response_error = port_state_.pending->error;
    port_state_.pending.reset();
  }

  void drive_memory_inputs() {
    dut_.memory_req_ready = request_ready() ? 1U : 0U;
    dut_.memory_rsp_valid = port_state_.response_valid ? 1U : 0U;
    dut_.memory_rsp_rdata = port_state_.response_data;
    dut_.memory_rsp_error = port_state_.response_error ? 1U : 0U;
  }

  void consume_response() {
    expect(port_state_.response_valid,
           "vector memory response consumed while invalid");
    port_state_.response_valid = false;
    port_state_.response_data = 0U;
    port_state_.response_error = false;
  }

  void schedule_response(std::uint32_t data, bool error) {
    expect(!port_state_.response_valid && !port_state_.pending.has_value(),
           "vector memory accepted multiple outstanding requests");
    port_state_.pending =
        PendingResponse{data, error, port_config_.response_latency};
  }

  void accept_request(bool write, std::uint32_t address,
                      std::uint32_t data, std::uint32_t strobe) {
    bool legal = true;
    std::uint32_t response_data = 0U;
    if (port_state_.fail_next_request) {
      legal = false;
      port_state_.fail_next_request = false;
    } else if (write) {
      expect(strobe != 0U, "vector write used an empty byte strobe");
      legal = memory_.write_word(address, data, strobe);
    } else {
      expect(strobe == 0U, "vector read used a nonzero byte strobe");
      legal = memory_.read_word(address, response_data);
    }

    if (write) {
      ++port_state_.write_requests;
      port_state_.write_strobes.push_back(strobe);
    } else {
      ++port_state_.read_requests;
    }
    schedule_response(response_data, !legal);
  }

  void drive_command(const Command& command) {
    dut_.command_opcode = command.opcode;
    dut_.command_src0_addr = command.source0;
    dut_.command_src1_addr = command.source1;
    dut_.command_dst_addr = command.destination;
    dut_.command_length = command.length;
    dut_.command_flags = command.flags;
    dut_.command_priority = 0U;
    dut_.command_id = command.command_id;
  }

  void clear_inputs() {
    dut_.clk = 0;
    dut_.rst_n = 0;
    dut_.command_valid = 0;
    dut_.response_ready = 0;
    drive_command(Command{});
    dut_.memory_req_ready = 0;
    dut_.memory_rsp_valid = 0;
    dut_.memory_rsp_rdata = 0U;
    dut_.memory_rsp_error = 0;
  }

  VerilatedContext context_;
  Vvector_test_top dut_;
  ScratchpadImage memory_;
  PortConfig port_config_;
  PortState port_state_;
  std::uint64_t cycle_ = 0U;
  std::uint64_t active_cycles_ = 0U;
  std::uint64_t stalled_cycles_ = 0U;
  std::uint64_t completed_elements_ = 0U;
};

std::uint32_t flag(unsigned bit) {
  return std::uint32_t{1} << bit;
}

std::size_t storage_bytes(std::size_t element_count) {
  const auto words =
      (element_count + kElementsPerWord - 1U) / kElementsPerWord;
  return words * soc::DATA_BYTES;
}

CommandResult verify_operation(
    Fixture& fixture, const Command& command,
    const std::vector<std::uint16_t>& source0,
    const std::vector<std::uint16_t>& source1, std::uint16_t scalar,
    bool hold_response = false) {
  const auto padded_bytes = storage_bytes(command.length);
  fixture.memory().write_elements(command.source0, source0);
  if (command.opcode == soc::CMD_OP_VECTOR_SCALE) {
    fixture.memory().write_elements(command.source1, {scalar});
  } else if (command.opcode != soc::CMD_OP_VECTOR_RELU) {
    fixture.memory().write_elements(command.source1, source1);
  }
  fixture.memory().fill(command.destination, padded_bytes,
                        kDestinationSentinel);

  const bool signed_mode =
      (command.flags & flag(soc::FLAG_SIGNED_BIT)) != 0U;
  const bool saturate =
      (command.flags & flag(soc::FLAG_SATURATE_BIT)) != 0U;
  const auto expected = model::vector_operation(
      command.opcode, source0, source1, scalar, signed_mode, saturate);
  const auto result = fixture.run_command(command, hold_response);

  expect(result.error == soc::ERR_NONE,
         "legal vector command returned an error");
  expect(result.result == command.length && result.cycles != 0U,
         "vector completion metadata is incorrect");
  expect(result.completed_elements == command.length,
         "vector element completion events are incorrect");
  expect(result.writes ==
             (command.length + kElementsPerWord - 1U) / kElementsPerWord,
         "vector write request count is incorrect");
  const auto word_count =
      (command.length + kElementsPerWord - 1U) / kElementsPerWord;
  std::size_t expected_reads = word_count;
  if (command.opcode == soc::CMD_OP_VECTOR_SCALE) {
    ++expected_reads;
  } else if (command.opcode != soc::CMD_OP_VECTOR_RELU) {
    expected_reads += word_count;
  }
  expect(result.reads == expected_reads,
         "vector read request count is incorrect");
  expect(fixture.memory().read_elements(command.destination, command.length) ==
             expected,
         "vector output differs from reference model");

  const auto valid_bytes = command.length * kElementBytes;
  if (valid_bytes < padded_bytes) {
    const auto padding = fixture.memory().read_bytes(
        command.destination + static_cast<std::uint32_t>(valid_bytes),
        padded_bytes - valid_bytes);
    expect(std::all_of(padding.begin(), padding.end(), [](std::uint8_t value) {
             return value == kDestinationSentinel;
           }),
           "partial vector write corrupted padding bytes");
  }
  return result;
}

void test_directed_operations(Fixture& fixture) {
  fixture.reset();
  fixture.configure_port(PortConfig{});

  verify_operation(
      fixture,
      Command{soc::CMD_OP_VECTOR_ADD, kSource0Base, kSource1Base,
              kDestinationBase, 5U, flag(soc::FLAG_SIGNED_BIT), 0x801U},
      {1U, 0xFFFFU, 30000U, 0x8000U, 7U},
      {2U, 2U, 10000U, 0xFFFFU, 9U}, 0U, true);

  verify_operation(
      fixture,
      Command{soc::CMD_OP_VECTOR_ADD, kSource0Base, kSource1Base,
              kDestinationBase, 3U,
              flag(soc::FLAG_SIGNED_BIT) | flag(soc::FLAG_SATURATE_BIT),
              0x802U},
      {30000U, 0x8000U, 100U}, {10000U, 0xFFFFU, 200U}, 0U);

  verify_operation(
      fixture,
      Command{soc::CMD_OP_VECTOR_MULTIPLY, kSource0Base, kSource1Base,
              kDestinationBase, 4U, flag(soc::FLAG_SATURATE_BIT), 0x803U},
      {2U, 1000U, 0xFFFFU, 10U}, {3U, 100U, 2U, 20U}, 0U);

  verify_operation(
      fixture,
      Command{soc::CMD_OP_VECTOR_SCALE, kSource0Base, kScalarAddress,
              kDestinationBase, 7U,
              flag(soc::FLAG_SIGNED_BIT) | flag(soc::FLAG_SATURATE_BIT),
              0x804U},
      {1U, 0xFFFFU, 1000U, 0x8000U, 5U, 6U, 7U}, {}, 3U);

  verify_operation(
      fixture,
      Command{soc::CMD_OP_VECTOR_RELU, kSource0Base, kSource1Base,
              kDestinationBase, 5U, flag(soc::FLAG_SIGNED_BIT), 0x805U},
      {0xFFFFU, 0U, 1U, 0x8000U, 0x7FFFU}, {}, 0U);

  verify_operation(
      fixture,
      Command{soc::CMD_OP_VECTOR_CLAMP, kSource0Base, kSource1Base,
              kDestinationBase, 5U, flag(soc::FLAG_SIGNED_BIT), 0x806U},
      {0xFFFFU, 2U, 10U, 100U, 9U},
      {7U, 7U, 7U, 0xFFFFU, 9U}, 0U);
}

void test_length_boundaries(Fixture& fixture) {
  fixture.reset();
  std::vector<std::uint16_t> one = {0x1234U};
  verify_operation(
      fixture,
      Command{soc::CMD_OP_VECTOR_RELU, kSource0Base, kSource1Base,
              kDestinationBase, 1U, 0U, 0x810U},
      one, {}, 0U);

  std::vector<std::uint16_t> maximum(soc::DEFAULT_MAX_VECTOR_LENGTH);
  for (std::size_t index = 0; index < maximum.size(); ++index) {
    maximum[index] = static_cast<std::uint16_t>(index * 17U);
  }
  verify_operation(
      fixture,
      Command{soc::CMD_OP_VECTOR_SCALE, kSource0Base, kScalarAddress,
              kDestinationBase, soc::DEFAULT_MAX_VECTOR_LENGTH, 0U, 0x811U},
      maximum, {}, 3U);
}

void test_memory_backpressure(Fixture& fixture) {
  fixture.reset();
  fixture.configure_port(PortConfig{3U, 1U, 2U});
  const std::vector<std::uint16_t> source0 = {
      1U, 2U, 3U, 4U, 5U, 6U, 7U, 8U, 9U};
  const std::vector<std::uint16_t> source1 = {
      9U, 8U, 7U, 6U, 5U, 4U, 3U, 2U, 1U};
  const Command command = {
      soc::CMD_OP_VECTOR_ADD, kSource0Base, kSource1Base,
      kDestinationBase, static_cast<std::uint32_t>(source0.size()),
      0U, 0x820U};

  const auto initial_stalls = fixture.dut().stalled_cycle;
  const auto result =
      verify_operation(fixture, command, source0, source1, 0U);
  expect(initial_stalls == 0U, "unexpected pre-command stall indication");
  expect(result.stalled_cycles != 0U,
         "memory delay did not produce vector stall cycles");
  expect(!fixture.port_state().write_strobes.empty() &&
             fixture.port_state().write_strobes.back() == 0x3U,
         "odd-length vector did not use a partial final strobe");
}

void expect_rejected(Fixture& fixture, const Command& command,
                     std::uint32_t expected_error) {
  const auto reads = fixture.port_state().read_requests;
  const auto writes = fixture.port_state().write_requests;
  const auto result = fixture.run_command(command);
  expect(result.error == expected_error && result.result == 0U,
         "invalid vector command returned the wrong error");
  expect(fixture.port_state().read_requests == reads &&
             fixture.port_state().write_requests == writes,
         "invalid vector command issued memory traffic");
}

void test_error_paths(Fixture& fixture) {
  fixture.reset();
  expect_rejected(
      fixture,
      Command{soc::CMD_OP_REDUCE_SUM, kSource0Base, kSource1Base,
              kDestinationBase, 4U, 0U, 0x830U},
      soc::ERR_OPCODE);
  expect_rejected(
      fixture,
      Command{soc::CMD_OP_VECTOR_ADD, kSource0Base, kSource1Base,
              kDestinationBase, 0U, 0U, 0x831U},
      soc::ERR_DIMENSION);
  expect_rejected(
      fixture,
      Command{soc::CMD_OP_VECTOR_ADD, kSource0Base, kSource1Base,
              kDestinationBase, soc::DEFAULT_MAX_VECTOR_LENGTH + 1U,
              0U, 0x832U},
      soc::ERR_DIMENSION);
  expect_rejected(
      fixture,
      Command{soc::CMD_OP_VECTOR_ADD, kSource0Base + 2U, kSource1Base,
              kDestinationBase, 4U, 0U, 0x833U},
      soc::ERR_ADDRESS);
  expect_rejected(
      fixture,
      Command{soc::CMD_OP_VECTOR_RELU,
              soc::SPM_BASE_ADDR + soc::SPM_SIZE_BYTES - soc::DATA_BYTES,
              kSource1Base,
              kDestinationBase,
              3U,
              0U,
              0x834U},
      soc::ERR_SPM_BOUNDS);

  fixture.fail_next_request();
  const auto memory_error = fixture.run_command(
      Command{soc::CMD_OP_VECTOR_RELU, kSource0Base, kSource1Base,
              kDestinationBase, 4U, 0U, 0x835U});
  expect(memory_error.error == soc::ERR_ADDRESS &&
             memory_error.writes == 0U,
         "memory read error did not abort vector command");
}

void test_reset_during_operation(Fixture& fixture) {
  fixture.reset();
  fixture.configure_port(PortConfig{1U, 0U, 4U});
  const Command command = {
      soc::CMD_OP_VECTOR_ADD, kSource0Base, kSource1Base,
      kDestinationBase, 16U, 0U, 0x840U};
  fixture.start_command(command);
  fixture.tick();
  expect(fixture.dut().busy && !fixture.dut().command_ready,
         "vector accelerator was not active before reset");
  fixture.reset();
  expect(!fixture.dut().busy && fixture.dut().command_ready &&
             !fixture.dut().response_valid && !fixture.dut().memory_req_valid,
         "reset did not return vector accelerator to idle");
}

void test_random_operations(Fixture& fixture, std::mt19937& random) {
  fixture.reset();
  std::uniform_int_distribution<std::uint32_t> opcode_distribution(
      soc::CMD_OP_VECTOR_ADD, soc::CMD_OP_VECTOR_CLAMP);
  std::uniform_int_distribution<std::uint32_t> length_distribution(
      1U, 64U);
  std::uniform_int_distribution<std::uint32_t> element_distribution(
      0U, std::numeric_limits<std::uint16_t>::max());
  std::uniform_int_distribution<std::uint32_t> flag_distribution(0U, 3U);
  std::uniform_int_distribution<unsigned> latency_distribution(0U, 3U);

  for (unsigned case_index = 0; case_index < kRandomCaseCount;
       ++case_index) {
    const auto opcode = opcode_distribution(random);
    const auto length = length_distribution(random);
    const auto flags = flag_distribution(random);
    std::vector<std::uint16_t> source0(length);
    std::vector<std::uint16_t> source1(length);
    for (auto& value : source0) {
      value = static_cast<std::uint16_t>(element_distribution(random));
    }
    for (auto& value : source1) {
      value = static_cast<std::uint16_t>(element_distribution(random));
    }
    const auto scalar =
        static_cast<std::uint16_t>(element_distribution(random));
    fixture.configure_port(
        PortConfig{4U, case_index % 4U, latency_distribution(random)});
    verify_operation(
        fixture,
        Command{opcode, kSource0Base, kSource1Base, kDestinationBase,
                length, flags, kCommandIdBase + 0x100U + case_index},
        source0, source1, scalar);
  }
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
    test_directed_operations(fixture);
    test_length_boundaries(fixture);
    test_memory_backpressure(fixture);
    test_error_paths(fixture);
    test_reset_during_operation(fixture);
    test_random_operations(fixture, random);
    std::cout << "PASS test=vector seed=" << seed << '\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL test=vector seed=" << seed
              << " reason=" << error.what() << '\n';
    return 1;
  }
}
