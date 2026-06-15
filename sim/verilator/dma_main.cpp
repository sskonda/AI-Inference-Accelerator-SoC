#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <optional>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#include "Vdma_test_top.h"
#include "sim_utils.hpp"
#include "soc_memory_map.hpp"
#include "soc_registers.hpp"
#include "verilated.h"

namespace {

constexpr std::uint32_t kAllByteStrobes =
    (std::uint32_t{1} << soc::DATA_BYTES) - 1U;
constexpr std::uint32_t kByteMask = 0xFFU;
constexpr unsigned kBitsPerByte = 8U;
constexpr unsigned kMaximumTransferCycles = 4096U;
constexpr unsigned kRandomTransferCount = 64U;
constexpr std::size_t kDirectedTransferBytes = 19U;
constexpr std::size_t kRandomMaximumTransferBytes = 128U;
constexpr std::uint8_t kDestinationSentinel = 0xA5U;

void expect(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

struct PortConfig {
  unsigned initial_ready_stall = 0U;
  unsigned ready_block_modulus = 0U;
  unsigned ready_block_residue = 0U;
  unsigned response_latency = 0U;
};

struct PendingResponse {
  std::uint32_t data;
  bool error;
  unsigned delay;
};

struct MemoryRequest {
  bool write;
  std::uint32_t address;
  std::uint32_t write_data;
  std::uint32_t write_strobe;
  bool burst_last;
};

struct PortState {
  bool response_valid = false;
  std::uint32_t response_data = 0U;
  bool response_error = false;
  std::optional<PendingResponse> pending;
  bool fail_next_request = false;
  std::size_t request_count = 0U;
  std::vector<bool> burst_last;
};

struct TransferResult {
  bool error;
  std::uint32_t error_code;
  std::uint64_t bytes_read;
  std::uint64_t bytes_written;
  std::uint64_t active_cycles;
  std::uint64_t stalled_cycles;
  std::size_t source_requests;
  std::size_t destination_requests;
};

class MemoryImage {
 public:
  MemoryImage()
      : scratchpad_(soc::SPM_SIZE_BYTES, 0U),
        dram_(soc::DRAM_SIZE_BYTES, 0U) {}

  void fill(std::uint32_t address, std::size_t length, std::uint8_t value) {
    auto [region, offset] = locate(address, length);
    std::fill(region->begin() + static_cast<std::ptrdiff_t>(offset),
              region->begin() + static_cast<std::ptrdiff_t>(offset + length),
              value);
  }

  void write_bytes(std::uint32_t address,
                   const std::vector<std::uint8_t>& bytes) {
    auto [region, offset] = locate(address, bytes.size());
    std::copy(bytes.begin(), bytes.end(),
              region->begin() + static_cast<std::ptrdiff_t>(offset));
  }

  std::vector<std::uint8_t> read_bytes(std::uint32_t address,
                                       std::size_t length) const {
    const auto [region, offset] = locate_const(address, length);
    return std::vector<std::uint8_t>(
        region->begin() + static_cast<std::ptrdiff_t>(offset),
        region->begin() + static_cast<std::ptrdiff_t>(offset + length));
  }

  bool read_word(std::uint32_t address, std::uint32_t& data) const {
    try {
      const auto bytes = read_bytes(address, soc::DATA_BYTES);
      data = 0U;
      for (std::size_t byte_index = 0; byte_index < bytes.size();
           ++byte_index) {
        data |= static_cast<std::uint32_t>(bytes[byte_index])
                << (byte_index * kBitsPerByte);
      }
      return true;
    } catch (const std::out_of_range&) {
      data = 0U;
      return false;
    }
  }

  bool write_word(std::uint32_t address, std::uint32_t data,
                  std::uint32_t strobe) {
    try {
      auto [region, offset] = locate(address, soc::DATA_BYTES);
      for (std::size_t byte_index = 0; byte_index < soc::DATA_BYTES;
           ++byte_index) {
        if ((strobe & (std::uint32_t{1} << byte_index)) != 0U) {
          (*region)[offset + byte_index] = static_cast<std::uint8_t>(
              (data >> (byte_index * kBitsPerByte)) & kByteMask);
        }
      }
      return true;
    } catch (const std::out_of_range&) {
      return false;
    }
  }

 private:
  using Region = std::vector<std::uint8_t>;

  std::pair<Region*, std::size_t> locate(std::uint32_t address,
                                          std::size_t length) {
    if (range_fits(address, length, soc::SPM_BASE_ADDR,
                   soc::SPM_SIZE_BYTES)) {
      return {&scratchpad_,
              static_cast<std::size_t>(address - soc::SPM_BASE_ADDR)};
    }
    if (range_fits(address, length, soc::DRAM_BASE_ADDR,
                   soc::DRAM_SIZE_BYTES)) {
      return {&dram_,
              static_cast<std::size_t>(address - soc::DRAM_BASE_ADDR)};
    }
    throw std::out_of_range("memory range is outside data regions");
  }

  std::pair<const Region*, std::size_t> locate_const(
      std::uint32_t address, std::size_t length) const {
    if (range_fits(address, length, soc::SPM_BASE_ADDR,
                   soc::SPM_SIZE_BYTES)) {
      return {&scratchpad_,
              static_cast<std::size_t>(address - soc::SPM_BASE_ADDR)};
    }
    if (range_fits(address, length, soc::DRAM_BASE_ADDR,
                   soc::DRAM_SIZE_BYTES)) {
      return {&dram_,
              static_cast<std::size_t>(address - soc::DRAM_BASE_ADDR)};
    }
    throw std::out_of_range("memory range is outside data regions");
  }

  static bool range_fits(std::uint32_t address, std::size_t length,
                         std::uint32_t base, std::size_t size) {
    if (address < base) {
      return false;
    }
    const std::uint64_t offset =
        static_cast<std::uint64_t>(address) - base;
    return offset <= size && length <= size - static_cast<std::size_t>(offset);
  }

  Region scratchpad_;
  Region dram_;
};

class Fixture {
 public:
  Fixture() : dut_(&context_) {
    clear_inputs();
    reset();
  }

  ~Fixture() { dut_.final(); }

  Vdma_test_top& dut() { return dut_; }
  MemoryImage& memory() { return memory_; }

  void set_source_config(const PortConfig& config) {
    source_config_ = config;
    source_config_epoch_ = cycle_;
  }

  void set_destination_config(const PortConfig& config) {
    destination_config_ = config;
    destination_config_epoch_ = cycle_;
  }

  void clear_port_config() {
    source_config_ = PortConfig{};
    destination_config_ = PortConfig{};
    source_config_epoch_ = cycle_;
    destination_config_epoch_ = cycle_;
  }

  void fail_next_source_request() {
    source_state_.fail_next_request = true;
  }

  void fail_next_destination_request() {
    destination_state_.fail_next_request = true;
  }

  const PortState& source_state() const { return source_state_; }
  const PortState& destination_state() const {
    return destination_state_;
  }

  void evaluate() { dut_.eval(); }

  void tick() {
    prepare_response(source_state_);
    prepare_response(destination_state_);
    drive_memory_inputs();

    dut_.clk = 0;
    dut_.eval();
    context_.timeInc(1);

    const bool source_request_fire =
        dut_.source_req_valid && dut_.source_req_ready;
    const bool source_response_fire =
        dut_.source_rsp_valid && dut_.source_rsp_ready;
    const bool destination_request_fire =
        dut_.destination_req_valid && dut_.destination_req_ready;
    const bool destination_response_fire =
        dut_.destination_rsp_valid && dut_.destination_rsp_ready;
    const std::optional<MemoryRequest> source_request =
        source_request_fire
            ? std::optional<MemoryRequest>(MemoryRequest{
                  static_cast<bool>(dut_.source_req_write),
                  dut_.source_req_addr,
                  dut_.source_req_wdata,
                  dut_.source_req_wstrb,
                  static_cast<bool>(dut_.source_req_last)})
            : std::nullopt;
    const std::optional<MemoryRequest> destination_request =
        destination_request_fire
            ? std::optional<MemoryRequest>(MemoryRequest{
                  static_cast<bool>(dut_.destination_req_write),
                  dut_.destination_req_addr,
                  dut_.destination_req_wdata,
                  dut_.destination_req_wstrb,
                  static_cast<bool>(dut_.destination_req_last)})
            : std::nullopt;

    dut_.clk = 1;
    dut_.eval();
    context_.timeInc(1);

    if (dut_.active_cycle) {
      ++active_cycles_;
    }
    if (dut_.stalled_cycle) {
      ++stalled_cycles_;
    }
    bytes_read_ += dut_.bytes_read_event;
    bytes_written_ += dut_.bytes_written_event;

    if (source_response_fire) {
      consume_response(source_state_);
    }
    if (destination_response_fire) {
      consume_response(destination_state_);
    }
    if (source_request.has_value()) {
      accept_source_request(*source_request);
    }
    if (destination_request.has_value()) {
      accept_destination_request(*destination_request);
    }

    dut_.clk = 0;
    dut_.eval();
    context_.timeInc(1);
    ++cycle_;
  }

  void reset() {
    dut_.start = 0;
    source_state_ = PortState{};
    destination_state_ = PortState{};
    active_cycles_ = 0U;
    stalled_cycles_ = 0U;
    bytes_read_ = 0U;
    bytes_written_ = 0U;
    cycle_ = 0U;
    source_config_epoch_ = 0U;
    destination_config_epoch_ = 0U;
    dut_.rst_n = 0;
    tick();
    tick();
    dut_.rst_n = 1;
    evaluate();
  }

  TransferResult transfer(std::uint32_t source, std::uint32_t destination,
                          std::uint32_t length) {
    const auto initial_source_requests = source_state_.request_count;
    const auto initial_destination_requests = destination_state_.request_count;
    const auto initial_bytes_read = bytes_read_;
    const auto initial_bytes_written = bytes_written_;
    const auto initial_active_cycles = active_cycles_;
    const auto initial_stalled_cycles = stalled_cycles_;

    dut_.source_address = source;
    dut_.destination_address = destination;
    dut_.length_bytes = length;
    dut_.start = 1;
    tick();
    dut_.start = 0;
    expect(dut_.start_accepted, "DMA did not acknowledge a start request");

    for (unsigned transfer_cycle = 0;
         transfer_cycle < kMaximumTransferCycles; ++transfer_cycle) {
      if (dut_.done) {
        return TransferResult{
            static_cast<bool>(dut_.error),
            dut_.error_code,
            bytes_read_ - initial_bytes_read,
            bytes_written_ - initial_bytes_written,
            active_cycles_ - initial_active_cycles,
            stalled_cycles_ - initial_stalled_cycles,
            source_state_.request_count - initial_source_requests,
            destination_state_.request_count -
                initial_destination_requests};
      }
      tick();
    }
    throw std::runtime_error("DMA transfer timed out");
  }

 private:
  static bool request_ready(const PortConfig& config,
                            std::uint64_t cycle) {
    if (cycle < config.initial_ready_stall) {
      return false;
    }
    if (config.ready_block_modulus == 0U) {
      return true;
    }
    return ((cycle - config.initial_ready_stall) %
            config.ready_block_modulus) != config.ready_block_residue;
  }

  static void prepare_response(PortState& state) {
    if (state.response_valid || !state.pending.has_value()) {
      return;
    }
    if (state.pending->delay != 0U) {
      --state.pending->delay;
      return;
    }
    state.response_valid = true;
    state.response_data = state.pending->data;
    state.response_error = state.pending->error;
    state.pending.reset();
  }

  static void consume_response(PortState& state) {
    expect(state.response_valid, "memory response consumed while invalid");
    state.response_valid = false;
    state.response_data = 0U;
    state.response_error = false;
  }

  static void schedule_response(PortState& state, std::uint32_t data,
                                bool error, unsigned delay) {
    expect(!state.response_valid && !state.pending.has_value(),
           "memory port accepted more than one outstanding request");
    state.pending = PendingResponse{data, error, delay};
  }

  void drive_memory_inputs() {
    dut_.source_req_ready =
        request_ready(source_config_, cycle_ - source_config_epoch_) ? 1U
                                                                     : 0U;
    dut_.source_rsp_valid = source_state_.response_valid ? 1U : 0U;
    dut_.source_rsp_rdata = source_state_.response_data;
    dut_.source_rsp_error = source_state_.response_error ? 1U : 0U;

    dut_.destination_req_ready =
        request_ready(destination_config_,
                      cycle_ - destination_config_epoch_)
            ? 1U
            : 0U;
    dut_.destination_rsp_valid =
        destination_state_.response_valid ? 1U : 0U;
    dut_.destination_rsp_rdata = destination_state_.response_data;
    dut_.destination_rsp_error =
        destination_state_.response_error ? 1U : 0U;
  }

  void accept_source_request(const MemoryRequest& request) {
    expect(!request.write,
           "DMA issued a write on the source port");
    expect(request.write_strobe == 0U,
           "DMA source read used nonzero byte strobes");
    std::uint32_t data = 0U;
    bool legal = memory_.read_word(request.address, data);
    if (source_state_.fail_next_request) {
      legal = false;
      source_state_.fail_next_request = false;
    }
    ++source_state_.request_count;
    source_state_.burst_last.push_back(request.burst_last);
    schedule_response(source_state_, data, !legal,
                      source_config_.response_latency);
  }

  void accept_destination_request(const MemoryRequest& request) {
    expect(request.write,
           "DMA issued a read on the destination port");
    expect(request.write_strobe != 0U &&
               (request.write_strobe & ~kAllByteStrobes) == 0U,
           "DMA destination write used an invalid byte strobe");
    bool legal = true;
    if (destination_state_.fail_next_request) {
      legal = false;
      destination_state_.fail_next_request = false;
    } else {
      legal = memory_.write_word(request.address, request.write_data,
                                 request.write_strobe);
    }
    ++destination_state_.request_count;
    destination_state_.burst_last.push_back(request.burst_last);
    schedule_response(destination_state_, 0U, !legal,
                      destination_config_.response_latency);
  }

  void clear_inputs() {
    dut_.clk = 0;
    dut_.rst_n = 0;
    dut_.start = 0;
    dut_.source_address = 0U;
    dut_.destination_address = 0U;
    dut_.length_bytes = 0U;
    dut_.source_req_ready = 0;
    dut_.source_rsp_valid = 0;
    dut_.source_rsp_rdata = 0U;
    dut_.source_rsp_error = 0;
    dut_.destination_req_ready = 0;
    dut_.destination_rsp_valid = 0;
    dut_.destination_rsp_rdata = 0U;
    dut_.destination_rsp_error = 0;
  }

  VerilatedContext context_;
  Vdma_test_top dut_;
  MemoryImage memory_;
  PortConfig source_config_;
  PortConfig destination_config_;
  PortState source_state_;
  PortState destination_state_;
  std::uint64_t cycle_ = 0U;
  std::uint64_t source_config_epoch_ = 0U;
  std::uint64_t destination_config_epoch_ = 0U;
  std::uint64_t active_cycles_ = 0U;
  std::uint64_t stalled_cycles_ = 0U;
  std::uint64_t bytes_read_ = 0U;
  std::uint64_t bytes_written_ = 0U;
};

std::vector<std::uint8_t> make_pattern(std::size_t length,
                                       std::uint32_t salt) {
  std::vector<std::uint8_t> pattern(length);
  for (std::size_t index = 0; index < length; ++index) {
    pattern[index] = static_cast<std::uint8_t>(
        (static_cast<std::uint32_t>(index) * 37U + salt) & kByteMask);
  }
  return pattern;
}

unsigned random_below(std::mt19937& random, unsigned limit) {
  return static_cast<unsigned>(random() % limit);
}

std::string bit_vector_string(const std::vector<bool>& values) {
  std::string text;
  for (const bool value : values) {
    if (!text.empty()) {
      text += ",";
    }
    text += value ? "1" : "0";
  }
  return text;
}

void expect_success(const TransferResult& result, std::size_t length,
                    const std::string& context) {
  expect(!result.error, context + ": unexpected DMA error");
  expect(result.error_code == soc::ERR_NONE,
         context + ": successful transfer retained an error code");
  expect(result.bytes_read == length && result.bytes_written == length,
         context + ": byte event totals are incorrect");
  const std::size_t expected_requests =
      (length + soc::DATA_BYTES - 1U) / soc::DATA_BYTES;
  expect(result.source_requests == expected_requests &&
             result.destination_requests == expected_requests,
         context + ": request count is incorrect");
}

void test_one_word(Fixture& fixture) {
  constexpr std::uint32_t kSource = soc::DRAM_BASE_ADDR + 0x100U;
  constexpr std::uint32_t kDestination = soc::SPM_BASE_ADDR + 0x200U;
  const auto pattern = make_pattern(soc::DATA_BYTES, 0x11U);
  fixture.memory().write_bytes(kSource, pattern);
  fixture.memory().fill(kDestination, soc::DATA_BYTES,
                        kDestinationSentinel);
  const auto result =
      fixture.transfer(kSource, kDestination, soc::DATA_BYTES);
  expect_success(result, soc::DATA_BYTES, "one-word transfer");
  expect(fixture.memory().read_bytes(kDestination, pattern.size()) == pattern,
         "one-word transfer data mismatch");
}

void test_partial_and_bursts(Fixture& fixture) {
  constexpr std::uint32_t kSource = soc::DRAM_BASE_ADDR + 0x400U;
  constexpr std::uint32_t kDestination = soc::SPM_BASE_ADDR + 0x800U;
  const auto pattern = make_pattern(kDirectedTransferBytes, 0x29U);
  fixture.memory().write_bytes(kSource, pattern);
  fixture.memory().fill(kDestination,
                        kDirectedTransferBytes + soc::DATA_BYTES,
                        kDestinationSentinel);

  const std::size_t source_last_begin =
      fixture.source_state().burst_last.size();
  const std::size_t destination_last_begin =
      fixture.destination_state().burst_last.size();
  const auto result = fixture.transfer(
      kSource, kDestination,
      static_cast<std::uint32_t>(kDirectedTransferBytes));
  expect_success(result, kDirectedTransferBytes,
                 "partial multiword transfer");
  expect(fixture.memory().read_bytes(kDestination, pattern.size()) == pattern,
         "partial transfer data mismatch");
  expect(fixture.memory().read_bytes(
             kDestination + static_cast<std::uint32_t>(pattern.size()),
             soc::DATA_BYTES) ==
             std::vector<std::uint8_t>(soc::DATA_BYTES,
                                       kDestinationSentinel),
         "partial transfer modified bytes beyond its length");

  const auto& source_last = fixture.source_state().burst_last;
  const auto& destination_last = fixture.destination_state().burst_last;
  const std::vector<bool> expected_last = {false, false, false, true, true};
  const std::vector<bool> observed_source(
      source_last.begin() + static_cast<std::ptrdiff_t>(source_last_begin),
      source_last.end());
  const std::vector<bool> observed_destination(
      destination_last.begin() +
          static_cast<std::ptrdiff_t>(destination_last_begin),
      destination_last.end());
  expect(observed_source == expected_last,
         "source logical burst boundaries are incorrect: " +
             bit_vector_string(observed_source));
  expect(observed_destination == expected_last,
         "destination logical burst boundaries are incorrect: " +
             bit_vector_string(observed_destination));
}

void test_backpressure(Fixture& fixture) {
  constexpr std::uint32_t kSourceA = soc::DRAM_BASE_ADDR + 0x1000U;
  constexpr std::uint32_t kDestinationA = soc::SPM_BASE_ADDR + 0x1400U;
  constexpr std::uint32_t kSourceB = soc::DRAM_BASE_ADDR + 0x1800U;
  constexpr std::uint32_t kDestinationB = soc::SPM_BASE_ADDR + 0x1C00U;
  constexpr std::size_t kLength = 32U;
  const auto pattern_a = make_pattern(kLength, 0x43U);
  const auto pattern_b = make_pattern(kLength, 0x57U);
  fixture.memory().write_bytes(kSourceA, pattern_a);
  fixture.memory().write_bytes(kSourceB, pattern_b);

  fixture.set_source_config(PortConfig{0U, 3U, 0U, 2U});
  const auto source_stalled = fixture.transfer(
      kSourceA, kDestinationA, static_cast<std::uint32_t>(kLength));
  expect_success(source_stalled, kLength, "source-backpressured transfer");
  expect(source_stalled.stalled_cycles != 0U &&
             source_stalled.active_cycles >
                 source_stalled.source_requests * 4U,
         "source backpressure did not extend active time");
  expect(fixture.memory().read_bytes(kDestinationA, kLength) == pattern_a,
         "source-backpressured transfer data mismatch");

  fixture.clear_port_config();
  fixture.set_destination_config(PortConfig{0U, 4U, 1U, 3U});
  const auto destination_stalled = fixture.transfer(
      kSourceB, kDestinationB, static_cast<std::uint32_t>(kLength));
  expect_success(destination_stalled, kLength,
                 "destination-backpressured transfer");
  expect(destination_stalled.stalled_cycles != 0U &&
             destination_stalled.active_cycles >
                 destination_stalled.destination_requests * 4U,
         "destination backpressure did not extend active time");
  expect(fixture.memory().read_bytes(kDestinationB, kLength) == pattern_b,
         "destination-backpressured transfer data mismatch");
  fixture.clear_port_config();
}

void test_zero_and_illegal(Fixture& fixture) {
  const auto source_requests = fixture.source_state().request_count;
  const auto destination_requests =
      fixture.destination_state().request_count;
  const auto zero = fixture.transfer(0U, 0U, 0U);
  expect(!zero.error && zero.bytes_read == 0U &&
             zero.bytes_written == 0U && zero.source_requests == 0U &&
             zero.destination_requests == 0U,
         "zero-length transfer was not a no-op completion");
  expect(fixture.source_state().request_count == source_requests &&
             fixture.destination_state().request_count ==
                 destination_requests,
         "zero-length transfer accessed memory");

  const auto unaligned =
      fixture.transfer(soc::DRAM_BASE_ADDR + 1U, soc::SPM_BASE_ADDR, 4U);
  expect(unaligned.error && unaligned.error_code == soc::ERR_ADDRESS &&
             unaligned.source_requests == 0U &&
             unaligned.destination_requests == 0U,
         "unaligned source address was not rejected");

  const auto illegal_region =
      fixture.transfer(0U, soc::SPM_BASE_ADDR, soc::DATA_BYTES);
  expect(illegal_region.error &&
             illegal_region.error_code == soc::ERR_ADDRESS &&
             illegal_region.source_requests == 0U,
         "illegal source region was not rejected");

  const auto crossing = fixture.transfer(
      soc::DRAM_BASE_ADDR,
      soc::SPM_BASE_ADDR +
          static_cast<std::uint32_t>(soc::SPM_SIZE_BYTES -
                                     soc::DATA_BYTES),
      soc::DATA_BYTES + 1U);
  expect(crossing.error && crossing.error_code == soc::ERR_ADDRESS &&
             crossing.destination_requests == 0U,
         "range crossing the scratchpad boundary was not rejected");
}

void test_memory_errors(Fixture& fixture) {
  constexpr std::uint32_t kSource = soc::DRAM_BASE_ADDR + 0x2000U;
  constexpr std::uint32_t kDestination = soc::SPM_BASE_ADDR + 0x2200U;
  fixture.memory().write_bytes(kSource,
                               make_pattern(soc::DATA_BYTES, 0x71U));

  fixture.fail_next_source_request();
  const auto read_error =
      fixture.transfer(kSource, kDestination, soc::DATA_BYTES);
  expect(read_error.error && read_error.error_code == soc::ERR_ADDRESS &&
             read_error.source_requests == 1U &&
             read_error.destination_requests == 0U,
         "source response error did not terminate the transfer");

  fixture.fail_next_destination_request();
  const auto write_error =
      fixture.transfer(kSource, kDestination, soc::DATA_BYTES);
  expect(write_error.error && write_error.error_code == soc::ERR_ADDRESS &&
             write_error.source_requests == 1U &&
             write_error.destination_requests == 1U &&
             write_error.bytes_written == 0U,
         "destination response error did not terminate the transfer");
}

void test_busy_rejection(Fixture& fixture) {
  constexpr std::uint32_t kSource = soc::DRAM_BASE_ADDR + 0x2800U;
  constexpr std::uint32_t kDestination = soc::SPM_BASE_ADDR + 0x2C00U;
  constexpr std::size_t kLength = 64U;
  const auto pattern = make_pattern(kLength, 0x83U);
  fixture.memory().write_bytes(kSource, pattern);
  fixture.set_source_config(PortConfig{5U, 0U, 0U, 1U});

  auto& dut = fixture.dut();
  dut.source_address = kSource;
  dut.destination_address = kDestination;
  dut.length_bytes = kLength;
  dut.start = 1;
  fixture.tick();
  dut.start = 0;
  expect(dut.start_accepted && dut.busy,
         "busy-rejection setup transfer did not start");

  dut.source_address = kSource + 0x100U;
  dut.destination_address = kDestination + 0x100U;
  dut.length_bytes = soc::DATA_BYTES;
  dut.start = 1;
  fixture.tick();
  dut.start = 0;
  expect(dut.start_rejected && dut.error &&
             dut.error_code == soc::ERR_DMA_BUSY && dut.busy,
         "start while busy was not rejected without stopping the transfer");

  bool completed = false;
  for (unsigned cycle = 0; cycle < kMaximumTransferCycles; ++cycle) {
    fixture.tick();
    if (dut.done) {
      expect(!dut.error, "original transfer failed after busy rejection");
      completed = true;
      break;
    }
  }
  expect(completed, "original transfer did not complete after busy rejection");
  expect(fixture.memory().read_bytes(kDestination, kLength) == pattern,
         "busy rejection corrupted the active transfer");
  fixture.clear_port_config();
}

void test_reset_during_transfer(Fixture& fixture) {
  constexpr std::uint32_t kSource = soc::DRAM_BASE_ADDR + 0x3000U;
  constexpr std::uint32_t kDestination = soc::SPM_BASE_ADDR + 0x3200U;
  constexpr std::size_t kLength = 16U;
  fixture.memory().write_bytes(kSource, make_pattern(kLength, 0x8FU));
  fixture.memory().fill(kDestination, kLength, kDestinationSentinel);
  fixture.set_source_config(PortConfig{0U, 1U, 0U, 0U});

  auto& dut = fixture.dut();
  dut.source_address = kSource;
  dut.destination_address = kDestination;
  dut.length_bytes = kLength;
  dut.start = 1;
  fixture.tick();
  dut.start = 0;
  fixture.tick();
  expect(dut.busy && dut.stalled_cycle,
         "reset test did not reach a stalled active transfer");

  fixture.reset();
  expect(!dut.busy && !dut.done && !dut.error &&
             !dut.source_req_valid && !dut.destination_req_valid,
         "reset did not clear DMA control state");
  expect(fixture.memory().read_bytes(kDestination, kLength) ==
             std::vector<std::uint8_t>(kLength, kDestinationSentinel),
         "reset transfer modified destination memory");
  fixture.clear_port_config();
}

void test_back_to_back_and_memory_copy(Fixture& fixture) {
  constexpr std::uint32_t kSourceA = soc::SPM_BASE_ADDR + 0x3400U;
  constexpr std::uint32_t kDestinationA = soc::DRAM_BASE_ADDR + 0x3800U;
  constexpr std::uint32_t kSourceB = soc::DRAM_BASE_ADDR + 0x3C00U;
  constexpr std::uint32_t kDestinationB = soc::DRAM_BASE_ADDR + 0x4000U;
  constexpr std::uint32_t kSourceC = soc::SPM_BASE_ADDR + 0x6000U;
  constexpr std::uint32_t kDestinationC = soc::SPM_BASE_ADDR + 0x6400U;
  constexpr std::size_t kLengthA = 12U;
  constexpr std::size_t kLengthB = 28U;
  constexpr std::size_t kLengthC = 20U;
  const auto pattern_a = make_pattern(kLengthA, 0x95U);
  const auto pattern_b = make_pattern(kLengthB, 0xA7U);
  const auto pattern_c = make_pattern(kLengthC, 0xB9U);
  fixture.memory().write_bytes(kSourceA, pattern_a);
  fixture.memory().write_bytes(kSourceB, pattern_b);
  fixture.memory().write_bytes(kSourceC, pattern_c);

  expect_success(fixture.transfer(kSourceA, kDestinationA, kLengthA),
                 kLengthA, "scratchpad-to-memory transfer");
  expect_success(fixture.transfer(kSourceB, kDestinationB, kLengthB),
                 kLengthB, "memory-to-memory transfer");
  expect_success(fixture.transfer(kSourceC, kDestinationC, kLengthC),
                 kLengthC, "scratchpad-to-scratchpad transfer");
  expect(fixture.memory().read_bytes(kDestinationA, kLengthA) == pattern_a,
         "back-to-back first transfer mismatch");
  expect(fixture.memory().read_bytes(kDestinationB, kLengthB) == pattern_b,
         "back-to-back second transfer mismatch");
  expect(fixture.memory().read_bytes(kDestinationC, kLengthC) == pattern_c,
         "back-to-back third transfer mismatch");
}

void test_random_transfers(Fixture& fixture, std::mt19937& random) {
  constexpr std::uint32_t kSourceWindowOffset = 0x1000U;
  constexpr std::uint32_t kDestinationWindowOffset = 0x4000U;
  constexpr std::uint32_t kWindowStride = 0x100U;

  for (unsigned transfer_index = 0;
       transfer_index < kRandomTransferCount; ++transfer_index) {
    const std::size_t length =
        1U + (random() % kRandomMaximumTransferBytes);
    const bool source_in_dram = (random() & 1U) != 0U;
    const bool destination_in_dram = (random() & 1U) != 0U;
    const std::uint32_t slot =
        (transfer_index % 32U) * kWindowStride;
    const std::uint32_t source =
        (source_in_dram ? soc::DRAM_BASE_ADDR : soc::SPM_BASE_ADDR) +
        kSourceWindowOffset + slot;
    const std::uint32_t destination =
        (destination_in_dram ? soc::DRAM_BASE_ADDR
                             : soc::SPM_BASE_ADDR) +
        kDestinationWindowOffset + slot;
    const auto pattern = make_pattern(length, random());
    fixture.memory().write_bytes(source, pattern);
    fixture.memory().fill(destination, length + soc::DATA_BYTES,
                          kDestinationSentinel);

    fixture.set_source_config(
        PortConfig{random_below(random, 3U),
                   2U + random_below(random, 4U),
                   random_below(random, 2U),
                   random_below(random, 4U)});
    fixture.set_destination_config(
        PortConfig{random_below(random, 3U),
                   2U + random_below(random, 5U),
                   random_below(random, 2U),
                   random_below(random, 4U)});
    const auto result = fixture.transfer(
        source, destination, static_cast<std::uint32_t>(length));
    expect_success(result, length, "random transfer");
    expect(fixture.memory().read_bytes(destination, length) == pattern,
           "random transfer data mismatch");
  }
  fixture.clear_port_config();
}

void run_directed(Fixture& fixture) {
  test_one_word(fixture);
  test_partial_and_bursts(fixture);
  test_backpressure(fixture);
  test_zero_and_illegal(fixture);
  test_memory_errors(fixture);
  test_busy_rejection(fixture);
  test_reset_during_transfer(fixture);
  test_back_to_back_and_memory_copy(fixture);
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
    } else if (argument == sim::kCoverageFileOption && (index + 1 < argc)) {
      ++index;
    } else if (!sim::is_coverage_argument(argument)) {
      std::cerr << "error: unknown argument: " << argument << '\n';
      return 2;
    }
  }

  try {
    Fixture fixture;
    run_directed(fixture);
    if (test_name == "regress") {
      std::mt19937 random(seed);
      test_random_transfers(fixture, random);
    } else if (test_name != "smoke") {
      throw std::runtime_error("unsupported test name: " + test_name);
    }
    sim::write_coverage_if_requested(argc, argv);
    std::cout << "PASS test=" << test_name << " seed=" << seed << '\n';
  } catch (const std::exception& error) {
    std::cerr << "FAIL test=" << test_name << " seed=" << seed
              << " reason=" << error.what() << '\n';
    return 1;
  }

  return 0;
}
