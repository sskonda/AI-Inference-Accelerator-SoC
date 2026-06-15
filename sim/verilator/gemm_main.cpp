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

#include "Vgemm_test_top.h"
#include "gemm_model.hpp"
#include "soc_memory_map.hpp"
#include "soc_registers.hpp"
#include "verilated.h"

namespace {

constexpr std::uint32_t kMatrixABase = soc::SPM_BASE_ADDR;
constexpr std::uint32_t kMatrixBBase = soc::SPM_BASE_ADDR + 0x2000U;
constexpr std::uint32_t kMatrixCBase = soc::SPM_BASE_ADDR + 0x4000U;
constexpr std::uint32_t kCommandIdBase = 0xB00U;
constexpr std::uint8_t kDestinationSentinel = 0xA5U;
constexpr unsigned kBitsPerByte = 8U;
constexpr unsigned kElementBytes = soc::ELEMENT_WIDTH / kBitsPerByte;
constexpr unsigned kMaximumCommandCycles = 50000U;
constexpr unsigned kRandomCaseCount = 80U;

void expect(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

std::size_t rounded_matrix_bytes(std::size_t elements) {
  const auto raw_bytes = elements * kElementBytes;
  return ((raw_bytes + soc::DATA_BYTES - 1U) / soc::DATA_BYTES) *
         soc::DATA_BYTES;
}

std::size_t expected_read_requests(std::size_t rows, std::size_t columns,
                                   std::size_t inner) {
  std::size_t requests = 0U;
  for (std::size_t row_base = 0U; row_base < rows;
       row_base += soc::DEFAULT_GEMM_TILE_M) {
    const auto tile_rows =
        std::min<std::size_t>(soc::DEFAULT_GEMM_TILE_M, rows - row_base);
    for (std::size_t column_base = 0U; column_base < columns;
         column_base += soc::DEFAULT_GEMM_TILE_N) {
      const auto tile_columns = std::min<std::size_t>(
          soc::DEFAULT_GEMM_TILE_N, columns - column_base);
      requests += inner * (tile_rows + tile_columns);
    }
  }
  return requests;
}

std::uint32_t flag(unsigned bit) {
  return std::uint32_t{1} << bit;
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
  bool fail_next_read = false;
  bool fail_next_write = false;
  std::size_t read_requests = 0U;
  std::size_t write_requests = 0U;
  std::size_t last_writes = 0U;
};

struct Command {
  std::uint32_t opcode = soc::CMD_OP_GEMM;
  std::uint32_t matrix_a = kMatrixABase;
  std::uint32_t matrix_b = kMatrixBBase;
  std::uint32_t matrix_c = kMatrixCBase;
  std::uint32_t rows = 1U;
  std::uint32_t columns = 1U;
  std::uint32_t inner = 1U;
  std::uint32_t flags = 0U;
  std::uint32_t command_id = kCommandIdBase;
};

struct CommandResult {
  std::uint32_t error;
  std::uint32_t result;
  std::uint32_t cycles;
  std::uint64_t active_cycles;
  std::uint64_t stalled_cycles;
  std::uint64_t completed_outputs;
  std::size_t reads;
  std::size_t writes;
  std::size_t last_writes;
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
    const auto offset = locate(address, values.size() * kElementBytes);
    for (std::size_t index = 0; index < values.size(); ++index) {
      bytes_[offset + index * kElementBytes] =
          static_cast<std::uint8_t>(values[index]);
      bytes_[offset + index * kElementBytes + 1U] =
          static_cast<std::uint8_t>(values[index] >> kBitsPerByte);
    }
  }

  std::vector<std::uint16_t> read_elements(std::uint32_t address,
                                           std::size_t count) const {
    const auto offset = locate(address, count * kElementBytes);
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

  Vgemm_test_top& dut() { return dut_; }
  ScratchpadImage& memory() { return memory_; }
  const PortState& port_state() const { return port_state_; }

  void configure_port(const PortConfig& config) { port_config_ = config; }
  void fail_next_read() { port_state_.fail_next_read = true; }
  void fail_next_write() { port_state_.fail_next_write = true; }
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
    const bool request_last = dut_.memory_req_last;
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
    completed_outputs_ += dut_.outputs_completed_event;

    if (response_fire) {
      consume_response();
    }
    if (request_fire) {
      accept_request(request_write, request_last, request_address,
                     request_data, request_strobe);
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
    completed_outputs_ = 0U;
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
    expect(dut_.command_ready, "GEMM command was not accepted while idle");
    tick();
    dut_.command_valid = 0;
    evaluate();
  }

  CommandResult finish_command(const Command& command,
                               bool hold_response = false) {
    const auto initial_reads = port_state_.read_requests;
    const auto initial_writes = port_state_.write_requests;
    const auto initial_last_writes = port_state_.last_writes;
    const auto initial_active = active_cycles_;
    const auto initial_stalled = stalled_cycles_;
    const auto initial_completed = completed_outputs_;

    bool saw_done = false;
    bool saw_error = false;
    for (unsigned wait_cycle = 0; wait_cycle < kMaximumCommandCycles;
         ++wait_cycle) {
      saw_done = saw_done || dut_.done;
      saw_error = saw_error || dut_.error;
      if (dut_.response_valid) {
        expect(dut_.response_command_id == command.command_id,
               "GEMM response command ID mismatch");
        expect(dut_.response_opcode == command.opcode,
               "GEMM response opcode mismatch");
        expect(saw_done, "GEMM response appeared without done event");
        expect(saw_error == (dut_.response_error != soc::ERR_NONE),
               "GEMM error event did not match response");

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
                 "GEMM response changed under backpressure");
        }

        const CommandResult result = {
            dut_.response_error,
            dut_.response_result,
            dut_.response_cycles,
            active_cycles_ - initial_active,
            stalled_cycles_ - initial_stalled,
            completed_outputs_ - initial_completed,
            port_state_.read_requests - initial_reads,
            port_state_.write_requests - initial_writes,
            port_state_.last_writes - initial_last_writes};
        dut_.response_ready = 1;
        tick();
        dut_.response_ready = 0;
        evaluate();
        expect(!dut_.busy && !dut_.response_valid,
               "GEMM accelerator did not retire response");
        return result;
      }
      tick();
    }
    throw std::runtime_error("GEMM command timed out");
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
           "GEMM memory response consumed while invalid");
    port_state_.response_valid = false;
    port_state_.response_data = 0U;
    port_state_.response_error = false;
  }

  void schedule_response(std::uint32_t data, bool error) {
    expect(!port_state_.response_valid && !port_state_.pending.has_value(),
           "GEMM memory accepted multiple outstanding requests");
    port_state_.pending =
        PendingResponse{data, error, port_config_.response_latency};
  }

  void accept_request(bool write, bool last, std::uint32_t address,
                      std::uint32_t data, std::uint32_t strobe) {
    bool legal = true;
    std::uint32_t response_data = 0U;
    expect((address % soc::DATA_BYTES) == 0U,
           "GEMM issued an unaligned memory request");
    if (write) {
      const auto lane_zero_strobe =
          (std::uint32_t{1} << kElementBytes) - 1U;
      const auto lane_one_strobe = lane_zero_strobe << kElementBytes;
      expect(strobe == lane_zero_strobe || strobe == lane_one_strobe,
             "GEMM result write used an invalid byte strobe");
      if (port_state_.fail_next_write) {
        legal = false;
        port_state_.fail_next_write = false;
      } else {
        legal = memory_.write_word(address, data, strobe);
      }
      ++port_state_.write_requests;
      if (last) {
        ++port_state_.last_writes;
      }
    } else {
      expect(strobe == 0U, "GEMM read used a nonzero byte strobe");
      expect(!last, "GEMM read incorrectly marked the end of a command");
      if (port_state_.fail_next_read) {
        legal = false;
        port_state_.fail_next_read = false;
      } else {
        legal = memory_.read_word(address, response_data);
      }
      ++port_state_.read_requests;
    }
    schedule_response(response_data, !legal);
  }

  void drive_command(const Command& command) {
    dut_.command_opcode = command.opcode;
    dut_.command_src0_addr = command.matrix_a;
    dut_.command_src1_addr = command.matrix_b;
    dut_.command_dst_addr = command.matrix_c;
    dut_.command_m = command.rows;
    dut_.command_n = command.columns;
    dut_.command_k = command.inner;
    dut_.command_flags = command.flags;
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
  Vgemm_test_top dut_;
  ScratchpadImage memory_;
  PortConfig port_config_;
  PortState port_state_;
  std::uint64_t cycle_ = 0U;
  std::uint64_t active_cycles_ = 0U;
  std::uint64_t stalled_cycles_ = 0U;
  std::uint64_t completed_outputs_ = 0U;
};

CommandResult verify_operation(
    Fixture& fixture, const Command& command,
    const std::vector<std::uint16_t>& matrix_a,
    const std::vector<std::uint16_t>& matrix_b, bool hold_response = false) {
  fixture.memory().write_elements(command.matrix_a, matrix_a);
  fixture.memory().write_elements(command.matrix_b, matrix_b);
  const auto output_elements =
      static_cast<std::size_t>(command.rows) * command.columns;
  const auto output_storage = rounded_matrix_bytes(output_elements);
  fixture.memory().fill(command.matrix_c, output_storage,
                        kDestinationSentinel);

  const bool signed_mode =
      (command.flags & flag(soc::FLAG_SIGNED_BIT)) != 0U;
  const bool saturate =
      (command.flags & flag(soc::FLAG_SATURATE_BIT)) != 0U;
  const auto expected = model::gemm_operation(
      matrix_a, matrix_b, command.rows, command.columns, command.inner,
      signed_mode, saturate);
  const auto result = fixture.run_command(command, hold_response);

  expect(result.error == soc::ERR_NONE, "legal GEMM command returned an error");
  expect(result.result == output_elements && result.cycles != 0U,
         "GEMM completion metadata is incorrect");
  expect(result.completed_outputs == output_elements,
         "GEMM output completion event count is incorrect");
  expect(result.reads == expected_read_requests(
                             command.rows, command.columns, command.inner),
         "GEMM read request count does not match tiled execution");
  expect(result.writes == output_elements,
         "GEMM write request count is incorrect");
  expect(result.last_writes == 1U,
         "GEMM did not mark exactly one final output write");
  expect(fixture.memory().read_elements(command.matrix_c, output_elements) ==
             expected,
         "GEMM scratchpad output differs from reference model");

  const auto raw_output_bytes = output_elements * kElementBytes;
  if (output_storage > raw_output_bytes) {
    const auto padding = fixture.memory().read_bytes(
        command.matrix_c + static_cast<std::uint32_t>(raw_output_bytes),
        output_storage - raw_output_bytes);
    expect(std::all_of(padding.begin(), padding.end(), [](std::uint8_t value) {
             return value == kDestinationSentinel;
           }),
           "GEMM output write corrupted matrix padding");
  }
  return result;
}

void expect_rejected(Fixture& fixture, const Command& command,
                     std::uint32_t expected_error) {
  const auto reads = fixture.port_state().read_requests;
  const auto writes = fixture.port_state().write_requests;
  const auto result = fixture.run_command(command);
  expect(result.error == expected_error && result.result == 0U,
         "invalid GEMM command returned the wrong error");
  expect(fixture.port_state().read_requests == reads &&
             fixture.port_state().write_requests == writes,
         "invalid GEMM command issued memory traffic");
}

void test_directed_operations(Fixture& fixture) {
  fixture.reset();
  fixture.configure_port(PortConfig{});

  verify_operation(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              1U, 1U, 1U, flag(soc::FLAG_SIGNED_BIT), 0xB01U},
      {static_cast<std::uint16_t>(-7)},
      {static_cast<std::uint16_t>(6)}, true);

  verify_operation(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              2U, 2U, 2U, 0U, 0xB02U},
      {1U, 2U, 3U, 4U}, {1U, 0U, 0U, 1U});

  verify_operation(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              3U, 4U, 2U, flag(soc::FLAG_SIGNED_BIT), 0xB03U},
      {1U, 2U, 3U, 4U, 5U, 6U},
      {1U, 2U, 3U, 4U, 5U, 6U, 7U, 8U});

  verify_operation(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              3U, 2U, 1U, 0U, 0xB04U},
      {2U, 3U, 4U}, {5U, 6U});

  verify_operation(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              3U, 3U, 3U, 0U, 0xB05U},
      std::vector<std::uint16_t>(9U, 0U),
      {1U, 0U, 0U, 0U, 1U, 0U, 0U, 0U, 1U});

  verify_operation(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              1U, 1U, 2U, 0U, 0xB06U},
      {std::numeric_limits<std::uint16_t>::max(),
       std::numeric_limits<std::uint16_t>::max()},
      {2U, 2U});

  verify_operation(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              1U, 1U, 2U, flag(soc::FLAG_SATURATE_BIT), 0xB07U},
      {std::numeric_limits<std::uint16_t>::max(),
       std::numeric_limits<std::uint16_t>::max()},
      {2U, 2U});

  verify_operation(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              1U, 1U, 2U,
              flag(soc::FLAG_SIGNED_BIT) | flag(soc::FLAG_SATURATE_BIT),
              0xB08U},
      {static_cast<std::uint16_t>(-30000),
       static_cast<std::uint16_t>(-30000)},
      {2U, 2U});
}

void test_maximum_dimensions(Fixture& fixture) {
  fixture.reset();
  std::vector<std::uint16_t> matrix_a(
      soc::DEFAULT_MAX_GEMM_M * soc::DEFAULT_MAX_GEMM_K);
  std::vector<std::uint16_t> matrix_b(
      soc::DEFAULT_MAX_GEMM_K * soc::DEFAULT_MAX_GEMM_N);
  for (std::size_t index = 0; index < matrix_a.size(); ++index) {
    matrix_a[index] = static_cast<std::uint16_t>((index * 13U) & 0xFFU);
  }
  for (std::size_t index = 0; index < matrix_b.size(); ++index) {
    matrix_b[index] = static_cast<std::uint16_t>((index * 7U) & 0xFFU);
  }
  verify_operation(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              soc::DEFAULT_MAX_GEMM_M, soc::DEFAULT_MAX_GEMM_N,
              soc::DEFAULT_MAX_GEMM_K, 0U, 0xB10U},
      matrix_a, matrix_b);
}

void test_tiling_and_backpressure(Fixture& fixture) {
  fixture.reset();
  fixture.configure_port(PortConfig{3U, 1U, 2U});
  const std::vector<std::uint16_t> matrix_a = {
      1U, 2U, 3U, 4U, 5U, 6U, 7U, 8U,
      9U, 10U, 11U, 12U, 13U, 14U, 15U, 16U};
  const std::vector<std::uint16_t> matrix_b = {
      1U, 0U, 0U, 1U, 2U, 1U, 1U, 2U,
      3U, 2U, 2U, 3U, 4U, 3U, 3U, 4U};
  const auto result = verify_operation(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              4U, 4U, 4U, 0U, 0xB20U},
      matrix_a, matrix_b);
  expect(result.stalled_cycles != 0U,
         "memory delay did not produce GEMM stall cycles");
  const auto naive_reads = 2U * 4U * 4U * 4U;
  expect(result.reads < naive_reads,
         "GEMM tile reuse did not reduce source reads");
}

void test_error_paths(Fixture& fixture) {
  fixture.reset();
  expect_rejected(
      fixture,
      Command{soc::CMD_OP_VECTOR_ADD, kMatrixABase, kMatrixBBase,
              kMatrixCBase, 2U, 2U, 2U, 0U, 0xB30U},
      soc::ERR_OPCODE);
  expect_rejected(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              0U, 2U, 2U, 0U, 0xB31U},
      soc::ERR_DIMENSION);
  expect_rejected(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              soc::DEFAULT_MAX_GEMM_M + 1U, 2U, 2U, 0U, 0xB32U},
      soc::ERR_DIMENSION);
  expect_rejected(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase + 2U, kMatrixBBase,
              kMatrixCBase, 2U, 2U, 2U, 0U, 0xB33U},
      soc::ERR_ADDRESS);
  expect_rejected(
      fixture,
      Command{soc::CMD_OP_GEMM,
              soc::SPM_BASE_ADDR +
                  static_cast<std::uint32_t>(soc::SPM_SIZE_BYTES) -
                  soc::DATA_BYTES,
              kMatrixBBase, kMatrixCBase, 2U, 2U, 2U, 0U, 0xB34U},
      soc::ERR_SPM_BOUNDS);
  expect_rejected(
      fixture,
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixABase,
              2U, 2U, 2U, 0U, 0xB35U},
      soc::ERR_ADDRESS);

  fixture.memory().write_elements(kMatrixABase, {1U, 2U, 3U, 4U});
  fixture.memory().write_elements(kMatrixBBase, {1U, 0U, 0U, 1U});
  fixture.fail_next_read();
  const auto read_error = fixture.run_command(
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              2U, 2U, 2U, 0U, 0xB36U});
  expect(read_error.error == soc::ERR_ADDRESS && read_error.writes == 0U,
         "GEMM read error did not abort the command");

  fixture.fail_next_write();
  const auto write_error = fixture.run_command(
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              2U, 2U, 2U, 0U, 0xB37U});
  expect(write_error.error == soc::ERR_ADDRESS && write_error.writes == 1U,
         "GEMM write error did not return an error");
}

void test_reset_during_operation(Fixture& fixture) {
  fixture.reset();
  fixture.configure_port(PortConfig{1U, 0U, 4U});
  fixture.start_command(
      Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
              4U, 4U, 4U, 0U, 0xB40U});
  fixture.tick();
  expect(fixture.dut().busy && !fixture.dut().command_ready,
         "GEMM accelerator was not active before reset");
  fixture.reset();
  expect(!fixture.dut().busy && fixture.dut().command_ready &&
             !fixture.dut().response_valid && !fixture.dut().memory_req_valid,
         "reset did not return GEMM accelerator to idle");
}

void test_random_operations(Fixture& fixture, std::mt19937& random) {
  fixture.reset();
  std::uniform_int_distribution<std::uint32_t> row_distribution(
      1U, soc::DEFAULT_MAX_GEMM_M);
  std::uniform_int_distribution<std::uint32_t> column_distribution(
      1U, soc::DEFAULT_MAX_GEMM_N);
  std::uniform_int_distribution<std::uint32_t> inner_distribution(
      1U, soc::DEFAULT_MAX_GEMM_K);
  std::uniform_int_distribution<std::uint32_t> element_distribution(
      0U, std::numeric_limits<std::uint16_t>::max());
  std::uniform_int_distribution<std::uint32_t> flag_distribution(0U, 3U);
  std::uniform_int_distribution<unsigned> latency_distribution(0U, 3U);

  for (unsigned case_index = 0; case_index < kRandomCaseCount;
       ++case_index) {
    const auto rows = row_distribution(random);
    const auto columns = column_distribution(random);
    const auto inner = inner_distribution(random);
    std::vector<std::uint16_t> matrix_a(rows * inner);
    std::vector<std::uint16_t> matrix_b(inner * columns);
    for (auto& value : matrix_a) {
      value = static_cast<std::uint16_t>(element_distribution(random));
    }
    for (auto& value : matrix_b) {
      value = static_cast<std::uint16_t>(element_distribution(random));
    }
    fixture.configure_port(
        PortConfig{4U, case_index % 4U, latency_distribution(random)});
    verify_operation(
        fixture,
        Command{soc::CMD_OP_GEMM, kMatrixABase, kMatrixBBase, kMatrixCBase,
                rows, columns, inner, flag_distribution(random),
                kCommandIdBase + 0x100U + case_index},
        matrix_a, matrix_b);
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
    test_maximum_dimensions(fixture);
    test_tiling_and_backpressure(fixture);
    test_error_paths(fixture);
    test_reset_during_operation(fixture);
    test_random_operations(fixture, random);
    std::cout << "PASS test=gemm seed=" << seed << '\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL test=gemm seed=" << seed
              << " reason=" << error.what() << '\n';
    return 1;
  }
}
