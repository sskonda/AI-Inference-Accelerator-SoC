#include <cstdint>
#include <deque>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#include "Vprimitive_test_top.h"
#include "sim_utils.hpp"
#include "verilated.h"

namespace {

constexpr std::uint32_t kScratchpadBase = 0x10000000U;
constexpr std::uint32_t kScratchpadSize = 64U;
constexpr std::uint32_t kFullWriteStrobe = 0xFU;
constexpr std::uint32_t kByteMask = 0xFFU;
constexpr unsigned kBitsPerByte = 8U;
constexpr std::size_t kFifoDepth = 4U;
constexpr std::size_t kNonPowerOfTwoFifoDepth = 3U;
constexpr std::size_t kRamDepth = 8U;
constexpr unsigned kRandomFifoCycles = 1000U;
constexpr unsigned kRandomRamCycles = 200U;

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

  Vprimitive_test_top& dut() { return dut_; }

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
    dut_.eval();
  }

  void clear_inputs() {
    dut_.clk = 0;
    dut_.rst_n = 0;
    dut_.fifo_push_valid = 0;
    dut_.fifo_push_data = 0;
    dut_.fifo_pop_ready = 0;
    dut_.fifo_one_push_valid = 0;
    dut_.fifo_one_push_data = 0;
    dut_.fifo_one_pop_ready = 0;
    dut_.fifo_three_push_valid = 0;
    dut_.fifo_three_push_data = 0;
    dut_.fifo_three_pop_ready = 0;
    dut_.skid_input_valid = 0;
    dut_.skid_input_data = 0;
    dut_.skid_output_ready = 0;
    dut_.ram_rd_en = 0;
    dut_.ram_rd_addr = 0;
    dut_.ram_wr_en = 0;
    dut_.ram_wr_addr = 0;
    dut_.ram_wr_data = 0;
    dut_.ram_wr_strb = 0;
    dut_.spm_rd_en = 0;
    dut_.spm_rd_addr = 0;
    dut_.spm_wr_en = 0;
    dut_.spm_wr_addr = 0;
    dut_.spm_wr_data = 0;
    dut_.spm_wr_strb = 0;
  }

 private:
  VerilatedContext context_;
  Vprimitive_test_top dut_;
};

void push_fifo(Fixture& fixture, std::uint8_t value) {
  auto& dut = fixture.dut();
  dut.fifo_push_valid = 1;
  dut.fifo_push_data = value;
  dut.fifo_pop_ready = 0;
  fixture.evaluate();
  expect(dut.fifo_push_ready, "FIFO rejected a legal push");
  fixture.tick();
  dut.fifo_push_valid = 0;
}

std::uint8_t pop_fifo(Fixture& fixture) {
  auto& dut = fixture.dut();
  dut.fifo_push_valid = 0;
  dut.fifo_pop_ready = 1;
  fixture.evaluate();
  expect(dut.fifo_pop_valid, "FIFO did not present queued data");
  const auto value = static_cast<std::uint8_t>(dut.fifo_pop_data);
  fixture.tick();
  dut.fifo_pop_ready = 0;
  return value;
}

void test_fifo_directed(Fixture& fixture) {
  auto& dut = fixture.dut();
  expect(dut.fifo_empty && !dut.fifo_full && dut.fifo_occupancy == 0,
         "FIFO reset state is incorrect");

  const std::vector<std::uint8_t> values = {0x11U, 0x22U, 0x33U, 0x44U};
  for (const auto value : values) {
    push_fifo(fixture, value);
  }
  expect(dut.fifo_full && !dut.fifo_empty && dut.fifo_occupancy == kFifoDepth,
         "FIFO did not enter full state");

  dut.fifo_push_valid = 1;
  dut.fifo_push_data = 0x55U;
  dut.fifo_pop_ready = 0;
  fixture.evaluate();
  expect(!dut.fifo_push_ready, "FIFO accepted data while full without a pop");
  fixture.tick();

  dut.fifo_pop_ready = 1;
  fixture.evaluate();
  expect(dut.fifo_push_ready && dut.fifo_pop_valid && dut.fifo_pop_data == values.front(),
         "FIFO full simultaneous push/pop handshake is incorrect");
  fixture.tick();
  dut.fifo_push_valid = 0;
  dut.fifo_pop_ready = 0;
  expect(dut.fifo_occupancy == kFifoDepth, "FIFO occupancy changed on simultaneous transfer");

  const std::vector<std::uint8_t> expected = {0x22U, 0x33U, 0x44U, 0x55U};
  for (const auto value : expected) {
    expect(pop_fifo(fixture) == value, "FIFO output order is incorrect");
  }
  expect(dut.fifo_empty && !dut.fifo_full && dut.fifo_occupancy == 0,
         "FIFO did not return to empty");

  dut.fifo_pop_ready = 1;
  fixture.tick();
  dut.fifo_pop_ready = 0;
  expect(dut.fifo_empty, "FIFO underflow changed empty state");

  push_fifo(fixture, 0xA5U);
  fixture.reset();
  expect(dut.fifo_empty && dut.fifo_occupancy == 0, "FIFO reset did not clear occupancy");
}

void test_depth_one_fifo(Fixture& fixture) {
  auto& dut = fixture.dut();
  dut.fifo_one_push_valid = 1;
  dut.fifo_one_push_data = 0x31U;
  fixture.evaluate();
  expect(dut.fifo_one_push_ready, "Depth-one FIFO rejected its first push");
  fixture.tick();
  expect(dut.fifo_one_full && dut.fifo_one_pop_valid && dut.fifo_one_pop_data == 0x31U,
         "Depth-one FIFO did not retain data");

  dut.fifo_one_push_data = 0x62U;
  dut.fifo_one_pop_ready = 1;
  fixture.evaluate();
  expect(dut.fifo_one_push_ready, "Depth-one FIFO blocked simultaneous replacement");
  expect(dut.fifo_one_pop_data == 0x31U, "Depth-one FIFO replaced data before pop");
  fixture.tick();
  dut.fifo_one_push_valid = 0;
  dut.fifo_one_pop_ready = 0;
  expect(dut.fifo_one_full && dut.fifo_one_pop_data == 0x62U,
         "Depth-one FIFO did not retain replacement data");

  dut.fifo_one_pop_ready = 1;
  fixture.tick();
  dut.fifo_one_pop_ready = 0;
  expect(dut.fifo_one_empty && !dut.fifo_one_full, "Depth-one FIFO did not become empty");
}

void test_non_power_of_two_fifo(Fixture& fixture) {
  auto& dut = fixture.dut();
  const std::vector<std::uint8_t> values = {0x17U, 0x29U, 0x3BU};

  for (const auto value : values) {
    dut.fifo_three_push_valid = 1;
    dut.fifo_three_push_data = value;
    fixture.evaluate();
    expect(dut.fifo_three_push_ready, "Depth-three FIFO rejected a legal push");
    fixture.tick();
  }
  dut.fifo_three_push_valid = 0;
  expect(dut.fifo_three_full &&
             dut.fifo_three_occupancy == static_cast<unsigned>(kNonPowerOfTwoFifoDepth),
         "Depth-three FIFO did not enter full state");

  for (const auto value : values) {
    dut.fifo_three_pop_ready = 1;
    fixture.evaluate();
    expect(dut.fifo_three_pop_valid && dut.fifo_three_pop_data == value,
           "Depth-three FIFO pointer wrap changed ordering");
    fixture.tick();
  }
  dut.fifo_three_pop_ready = 0;
  expect(dut.fifo_three_empty && dut.fifo_three_occupancy == 0,
         "Depth-three FIFO did not return to empty");
}

void test_skid_buffer(Fixture& fixture) {
  auto& dut = fixture.dut();
  dut.skid_input_valid = 1;
  dut.skid_input_data = 0x12U;
  dut.skid_output_ready = 1;
  fixture.evaluate();
  expect(dut.skid_input_ready && dut.skid_output_valid && dut.skid_output_data == 0x12U,
         "Skid buffer failed pass-through transfer");
  fixture.tick();

  dut.skid_input_data = 0x34U;
  dut.skid_output_ready = 0;
  fixture.evaluate();
  expect(dut.skid_input_ready && dut.skid_output_valid && dut.skid_output_data == 0x34U,
         "Skid buffer did not accept a stalled transfer");
  fixture.tick();

  dut.skid_input_valid = 0;
  fixture.evaluate();
  expect(!dut.skid_input_ready && dut.skid_output_valid && dut.skid_output_data == 0x34U,
         "Skid buffer did not hold stalled data");
  fixture.tick();

  dut.skid_input_valid = 1;
  dut.skid_input_data = 0x56U;
  dut.skid_output_ready = 1;
  fixture.evaluate();
  expect(dut.skid_input_ready && dut.skid_output_data == 0x34U,
         "Skid buffer did not present the oldest item");
  fixture.tick();

  dut.skid_input_valid = 0;
  dut.skid_output_ready = 0;
  fixture.evaluate();
  expect(dut.skid_output_valid && dut.skid_output_data == 0x56U,
         "Skid buffer did not replace a released item");
  dut.skid_output_ready = 1;
  fixture.tick();
  dut.skid_output_ready = 0;
  expect(!dut.skid_output_valid, "Skid buffer did not clear after output handshake");
}

void write_ram(Fixture& fixture, std::uint8_t address, std::uint32_t data,
               std::uint8_t strobe = kFullWriteStrobe) {
  auto& dut = fixture.dut();
  dut.ram_wr_en = 1;
  dut.ram_wr_addr = address;
  dut.ram_wr_data = data;
  dut.ram_wr_strb = strobe;
  fixture.tick();
  dut.ram_wr_en = 0;
  dut.ram_wr_strb = 0;
}

std::uint32_t read_ram(Fixture& fixture, std::uint8_t address) {
  auto& dut = fixture.dut();
  dut.ram_rd_en = 1;
  dut.ram_rd_addr = address;
  fixture.tick();
  expect(dut.ram_rd_valid, "RAM did not assert one-cycle read valid");
  const std::uint32_t value = dut.ram_rd_data;
  expect(!dut.ram_reg_rd_valid, "Registered RAM asserted valid too early");

  dut.ram_rd_en = 0;
  fixture.tick();
  expect(dut.ram_reg_rd_valid, "Registered RAM did not assert two-cycle read valid");
  expect(dut.ram_reg_rd_data == value, "Registered and unregistered RAM data differ");
  return value;
}

void test_ram_directed(Fixture& fixture) {
  auto& dut = fixture.dut();
  write_ram(fixture, 1U, 0x11223344U);
  expect(read_ram(fixture, 1U) == 0x11223344U, "RAM read/write mismatch");

  write_ram(fixture, 1U, 0xAABBCCDDU, 0x5U);
  expect(read_ram(fixture, 1U) == 0x11BB33DDU, "RAM byte enables are incorrect");

  write_ram(fixture, 2U, 0xCAFEBABEU);
  dut.ram_rd_en = 1;
  dut.ram_rd_addr = 2U;
  dut.ram_wr_en = 1;
  dut.ram_wr_addr = 2U;
  dut.ram_wr_data = 0x0BADF00DU;
  dut.ram_wr_strb = kFullWriteStrobe;
  fixture.tick();
  expect(dut.ram_rd_valid && dut.ram_rd_data == 0xCAFEBABEU,
         "RAM read-during-write is not read-first");
  dut.ram_rd_en = 0;
  dut.ram_wr_en = 0;
  dut.ram_wr_strb = 0;
  fixture.tick();
  expect(dut.ram_reg_rd_valid && dut.ram_reg_rd_data == 0xCAFEBABEU,
         "Registered RAM collision result is not read-first");
  expect(read_ram(fixture, 2U) == 0x0BADF00DU, "RAM collision write was not retained");

  write_ram(fixture, 3U, 0x13579BDFU);
  fixture.reset();
  expect(read_ram(fixture, 3U) == 0x13579BDFU, "RAM contents were reset unexpectedly");
}

void test_scratchpad(Fixture& fixture) {
  auto& dut = fixture.dut();
  const std::uint32_t legal_address = kScratchpadBase + 0x10U;

  dut.spm_wr_en = 1;
  dut.spm_wr_addr = legal_address;
  dut.spm_wr_data = 0x2468ACE0U;
  dut.spm_wr_strb = kFullWriteStrobe;
  fixture.evaluate();
  expect(!dut.spm_wr_error, "Scratchpad rejected a legal write");
  fixture.tick();
  dut.spm_wr_en = 0;
  dut.spm_wr_strb = 0;

  dut.spm_rd_en = 1;
  dut.spm_rd_addr = legal_address;
  fixture.evaluate();
  expect(!dut.spm_rd_error, "Scratchpad rejected a legal read");
  fixture.tick();
  expect(dut.spm_rd_valid && dut.spm_rd_data == 0x2468ACE0U,
         "Scratchpad read/write mismatch");
  dut.spm_rd_en = 0;
  fixture.tick();

  dut.spm_wr_en = 1;
  dut.spm_wr_addr = kScratchpadBase + kScratchpadSize;
  dut.spm_wr_strb = kFullWriteStrobe;
  fixture.evaluate();
  expect(dut.spm_wr_error, "Scratchpad accepted an out-of-bounds write");
  fixture.tick();
  dut.spm_wr_en = 0;

  dut.spm_rd_en = 1;
  dut.spm_rd_addr = kScratchpadBase + 1U;
  fixture.evaluate();
  expect(dut.spm_rd_error, "Scratchpad accepted a misaligned read");
  fixture.tick();
  dut.spm_rd_en = 0;
  expect(!dut.spm_rd_valid, "Scratchpad produced data for an illegal read");
}

void test_fifo_random(Fixture& fixture, std::mt19937& random) {
  auto& dut = fixture.dut();
  fixture.reset();
  std::deque<std::uint8_t> reference;
  bool source_valid = false;
  std::uint8_t source_data = 0;

  for (unsigned cycle = 0; cycle < kRandomFifoCycles; ++cycle) {
    if (!source_valid && (random() & 1U)) {
      source_valid = true;
      source_data = static_cast<std::uint8_t>(random());
    }
    const bool sink_ready = (random() & 1U) != 0U;
    dut.fifo_push_valid = source_valid;
    dut.fifo_push_data = source_data;
    dut.fifo_pop_ready = sink_ready;
    fixture.evaluate();

    const bool push_fire = source_valid && dut.fifo_push_ready;
    const bool pop_fire = dut.fifo_pop_valid && sink_ready;
    expect(dut.fifo_pop_valid == !reference.empty(), "Random FIFO valid mismatch");
    if (dut.fifo_pop_valid) {
      expect(dut.fifo_pop_data == reference.front(), "Random FIFO data mismatch");
    }

    fixture.tick();
    if (pop_fire) {
      reference.pop_front();
    }
    if (push_fire) {
      reference.push_back(source_data);
      source_valid = false;
    }
    expect(reference.size() <= kFifoDepth, "Reference FIFO overflowed");
    expect(dut.fifo_occupancy == reference.size(), "Random FIFO occupancy mismatch");
  }

  while (source_valid || !reference.empty()) {
    dut.fifo_push_valid = source_valid;
    dut.fifo_push_data = source_data;
    dut.fifo_pop_ready = 1;
    fixture.evaluate();
    const bool push_fire = source_valid && dut.fifo_push_ready;
    const bool pop_fire = dut.fifo_pop_valid;
    if (pop_fire) {
      expect(dut.fifo_pop_data == reference.front(), "Random FIFO drain mismatch");
    }
    fixture.tick();
    if (pop_fire) {
      reference.pop_front();
    }
    if (push_fire) {
      reference.push_back(source_data);
      source_valid = false;
    }
  }
  dut.fifo_push_valid = 0;
  dut.fifo_pop_ready = 0;
}

std::uint32_t apply_strobe(std::uint32_t old_value, std::uint32_t new_value,
                           std::uint8_t strobe) {
  std::uint32_t result = old_value;
  for (unsigned byte_index = 0; byte_index < sizeof(result); ++byte_index) {
    if ((strobe & (1U << byte_index)) != 0U) {
      const std::uint32_t byte_mask = kByteMask << (byte_index * kBitsPerByte);
      result = (result & ~byte_mask) | (new_value & byte_mask);
    }
  }
  return result;
}

void test_ram_random(Fixture& fixture, std::mt19937& random) {
  std::vector<std::uint32_t> reference(kRamDepth, 0U);
  for (std::size_t address = 0; address < kRamDepth; ++address) {
    write_ram(fixture, static_cast<std::uint8_t>(address), 0U);
  }

  for (unsigned cycle = 0; cycle < kRandomRamCycles; ++cycle) {
    const auto address = static_cast<std::uint8_t>(random() % kRamDepth);
    const std::uint32_t data = random();
    const auto strobe = static_cast<std::uint8_t>((random() % kFullWriteStrobe) + 1U);
    write_ram(fixture, address, data, strobe);
    reference[address] = apply_strobe(reference[address], data, strobe);

    const auto read_address = static_cast<std::uint8_t>(random() % kRamDepth);
    expect(read_ram(fixture, read_address) == reference[read_address],
           "Random RAM reference mismatch");
  }
}

void run_directed(Fixture& fixture) {
  test_fifo_directed(fixture);
  fixture.reset();
  test_depth_one_fifo(fixture);
  fixture.reset();
  test_non_power_of_two_fifo(fixture);
  fixture.reset();
  test_skid_buffer(fixture);
  fixture.reset();
  test_ram_directed(fixture);
  fixture.reset();
  test_scratchpad(fixture);
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
      test_fifo_random(fixture, random);
      test_ram_random(fixture, random);
    } else if (test_name != "smoke") {
      throw std::runtime_error("unsupported test name: " + test_name);
    }
    sim::write_coverage_if_requested(argc, argv);
    std::cout << "PASS test=" << test_name << " seed=" << seed << '\n';
  } catch (const std::exception& error) {
    std::cerr << "FAIL test=" << test_name << " seed=" << seed << " reason=" << error.what()
              << '\n';
    return 1;
  }

  return 0;
}
