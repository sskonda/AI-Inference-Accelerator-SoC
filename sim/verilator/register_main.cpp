#include <array>
#include <cstdint>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>

#include "Vregister_test_top.h"
#include "soc_registers.hpp"
#include "verilated.h"

namespace {

constexpr std::uint8_t kAllByteStrobes = 0xFU;
constexpr std::uint32_t kIllegalReadOffset = 0x080U;
constexpr std::uint32_t kIllegalWriteOffset = 0x084U;
constexpr unsigned kMaximumWaitCycles = 32U;
constexpr unsigned kRandomRegisterCycles = 250U;
constexpr std::uint32_t kSchedulerStarvationThreshold = 11U;

enum class WriteOrder {
  kTogether,
  kAddressFirst,
  kDataFirst,
};

struct ReadResult {
  std::uint32_t data;
  std::uint32_t response;
};

constexpr std::uint32_t bit(unsigned index) {
  return std::uint32_t{1} << index;
}

void expect(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

std::uint32_t apply_strobe(std::uint32_t old_value, std::uint32_t new_value,
                           std::uint8_t strobe) {
  std::uint32_t result = old_value;
  constexpr unsigned kBitsPerByte = 8U;
  constexpr std::uint32_t kByteMask = 0xFFU;
  for (unsigned byte_index = 0; byte_index < sizeof(result); ++byte_index) {
    if ((strobe & (std::uint8_t{1} << byte_index)) != 0U) {
      const std::uint32_t mask = kByteMask << (byte_index * kBitsPerByte);
      result = (result & ~mask) | (new_value & mask);
    }
  }
  return result;
}

class Fixture {
 public:
  Fixture() : dut_(&context_) {
    clear_inputs();
    reset();
  }

  ~Fixture() { dut_.final(); }

  Vregister_test_top& dut() { return dut_; }

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
    idle_bus();
    dut_.rst_n = 0;
    tick();
    tick();
    dut_.rst_n = 1;
    dut_.eval();
  }

  void send_write_address(std::uint32_t address) {
    dut_.axil_awvalid = 1;
    dut_.axil_awaddr = address;
    for (unsigned cycle = 0; cycle < kMaximumWaitCycles; ++cycle) {
      evaluate();
      if (dut_.axil_awready) {
        tick();
        dut_.axil_awvalid = 0;
        return;
      }
      tick();
    }
    throw std::runtime_error("AXI-Lite write address timed out");
  }

  void send_write_data(std::uint32_t data, std::uint8_t strobe) {
    dut_.axil_wvalid = 1;
    dut_.axil_wdata = data;
    dut_.axil_wstrb = strobe;
    for (unsigned cycle = 0; cycle < kMaximumWaitCycles; ++cycle) {
      evaluate();
      if (dut_.axil_wready) {
        tick();
        dut_.axil_wvalid = 0;
        return;
      }
      tick();
    }
    throw std::runtime_error("AXI-Lite write data timed out");
  }

  void send_write_together(std::uint32_t address, std::uint32_t data,
                           std::uint8_t strobe) {
    dut_.axil_awvalid = 1;
    dut_.axil_awaddr = address;
    dut_.axil_wvalid = 1;
    dut_.axil_wdata = data;
    dut_.axil_wstrb = strobe;

    bool address_sent = false;
    bool data_sent = false;
    for (unsigned cycle = 0; cycle < kMaximumWaitCycles; ++cycle) {
      evaluate();
      const bool address_fire = dut_.axil_awvalid && dut_.axil_awready;
      const bool data_fire = dut_.axil_wvalid && dut_.axil_wready;
      tick();
      if (address_fire) {
        address_sent = true;
        dut_.axil_awvalid = 0;
      }
      if (data_fire) {
        data_sent = true;
        dut_.axil_wvalid = 0;
      }
      if (address_sent && data_sent) {
        return;
      }
    }
    throw std::runtime_error("AXI-Lite combined write channels timed out");
  }

  std::uint32_t begin_write(std::uint32_t address, std::uint32_t data,
                            std::uint8_t strobe = kAllByteStrobes,
                            WriteOrder order = WriteOrder::kTogether) {
    dut_.axil_bready = 0;
    if (order == WriteOrder::kAddressFirst) {
      send_write_address(address);
      tick();
      send_write_data(data, strobe);
    } else if (order == WriteOrder::kDataFirst) {
      send_write_data(data, strobe);
      tick();
      send_write_address(address);
    } else {
      send_write_together(address, data, strobe);
    }

    for (unsigned cycle = 0; cycle < kMaximumWaitCycles; ++cycle) {
      evaluate();
      if (dut_.axil_bvalid) {
        return dut_.axil_bresp;
      }
      tick();
    }
    throw std::runtime_error("AXI-Lite write response timed out");
  }

  void hold_write_response(unsigned cycles) {
    const std::uint32_t response = dut_.axil_bresp;
    for (unsigned cycle = 0; cycle < cycles; ++cycle) {
      expect(dut_.axil_bvalid && dut_.axil_bresp == response,
             "AXI-Lite write response changed under backpressure");
      tick();
    }
  }

  void complete_write() {
    expect(dut_.axil_bvalid, "AXI-Lite write response disappeared before acceptance");
    dut_.axil_bready = 1;
    tick();
    dut_.axil_bready = 0;
    expect(!dut_.axil_bvalid, "AXI-Lite write response did not clear");
  }

  std::uint32_t write(std::uint32_t address, std::uint32_t data,
                      std::uint8_t strobe = kAllByteStrobes,
                      WriteOrder order = WriteOrder::kTogether,
                      unsigned response_stall_cycles = 0U) {
    const std::uint32_t response = begin_write(address, data, strobe, order);
    hold_write_response(response_stall_cycles);
    complete_write();
    return response;
  }

  ReadResult begin_read(std::uint32_t address) {
    dut_.axil_rready = 0;
    dut_.axil_arvalid = 1;
    dut_.axil_araddr = address;

    for (unsigned cycle = 0; cycle < kMaximumWaitCycles; ++cycle) {
      evaluate();
      if (dut_.axil_arready) {
        tick();
        dut_.axil_arvalid = 0;
        break;
      }
      tick();
      if (cycle + 1 == kMaximumWaitCycles) {
        throw std::runtime_error("AXI-Lite read address timed out");
      }
    }

    for (unsigned cycle = 0; cycle < kMaximumWaitCycles; ++cycle) {
      evaluate();
      if (dut_.axil_rvalid) {
        return ReadResult{dut_.axil_rdata, dut_.axil_rresp};
      }
      tick();
    }
    throw std::runtime_error("AXI-Lite read response timed out");
  }

  void hold_read_response(const ReadResult& expected, unsigned cycles) {
    for (unsigned cycle = 0; cycle < cycles; ++cycle) {
      expect(dut_.axil_rvalid && dut_.axil_rdata == expected.data &&
                 dut_.axil_rresp == expected.response,
             "AXI-Lite read response changed under backpressure");
      tick();
    }
  }

  void complete_read() {
    expect(dut_.axil_rvalid, "AXI-Lite read response disappeared before acceptance");
    dut_.axil_rready = 1;
    tick();
    dut_.axil_rready = 0;
    expect(!dut_.axil_rvalid, "AXI-Lite read response did not clear");
  }

  ReadResult read(std::uint32_t address, unsigned response_stall_cycles = 0U) {
    const ReadResult result = begin_read(address);
    hold_read_response(result, response_stall_cycles);
    complete_read();
    return result;
  }

 private:
  void idle_bus() {
    dut_.axil_awvalid = 0;
    dut_.axil_wvalid = 0;
    dut_.axil_bready = 0;
    dut_.axil_arvalid = 0;
    dut_.axil_rready = 0;
  }

  void clear_inputs() {
    dut_.clk = 0;
    dut_.rst_n = 0;
    dut_.axil_awvalid = 0;
    dut_.axil_awaddr = 0;
    dut_.axil_wvalid = 0;
    dut_.axil_wdata = 0;
    dut_.axil_wstrb = 0;
    dut_.axil_bready = 0;
    dut_.axil_arvalid = 0;
    dut_.axil_araddr = 0;
    dut_.axil_rready = 0;
    dut_.soc_busy = 0;
    dut_.irq_pending = 0;
    dut_.timer_value = 0;
    dut_.dma_busy = 0;
    dut_.dma_done = 0;
    dut_.dma_error = 0;
    dut_.queue_full = 0;
    dut_.queue_empty = 1;
    dut_.queue_occupancy = 0;
    dut_.queue_high_water = 0;
    dut_.perf_value = 0;
    dut_.cmd_ready = 0;
    dut_.cmd_full = 0;
    dut_.rsp_valid = 0;
    dut_.rsp_empty = 1;
    dut_.rsp_command_id = 0;
    dut_.rsp_opcode = 0;
    dut_.rsp_error = 0;
    dut_.rsp_result = 0;
    dut_.rsp_cycles = 0;
    dut_.hardware_error_set = 0;
  }

  VerilatedContext context_;
  Vregister_test_top dut_;
};

void expect_ok(const ReadResult& result, std::uint32_t expected,
               const std::string& message) {
  expect(result.response == soc::AXIL_RESP_OKAY, message + ": response");
  expect(result.data == expected, message + ": data");
}

void clear_errors(Fixture& fixture) {
  const auto current = fixture.read(soc::REG_ERROR_STATUS);
  expect(current.response == soc::AXIL_RESP_OKAY, "Error-status read failed");
  if (current.data != 0U) {
    expect(fixture.write(soc::REG_ERROR_STATUS, current.data) == soc::AXIL_RESP_OKAY,
           "Error-status clear failed");
  }
  expect_ok(fixture.read(soc::REG_ERROR_STATUS), 0U, "Error status did not clear");
}

void test_identity_and_bus(Fixture& fixture) {
  expect_ok(fixture.read(soc::REG_SOC_ID, 2U), soc::SOC_ID_VALUE, "SOC_ID mismatch");
  expect_ok(fixture.read(soc::REG_VERSION), soc::VERSION_VALUE, "VERSION mismatch");

  expect(fixture.write(soc::REG_IRQ_ENABLE, 0x15U, kAllByteStrobes,
                       WriteOrder::kAddressFirst, 2U) == soc::AXIL_RESP_OKAY,
         "Address-first write failed");
  expect_ok(fixture.read(soc::REG_IRQ_ENABLE), 0x15U, "IRQ enable mismatch");

  constexpr std::uint32_t kTimerInterval = 0x123456U;
  const std::uint32_t timer_control =
      (kTimerInterval << soc::TIMER_INTERVAL_LSB) | bit(soc::TIMER_ENABLE_BIT) |
      bit(soc::TIMER_PERIODIC_BIT);
  expect(fixture.write(soc::REG_TIMER_CTRL, timer_control, kAllByteStrobes,
                       WriteOrder::kDataFirst) == soc::AXIL_RESP_OKAY,
         "Data-first write failed");
  expect(fixture.dut().timer_enable && fixture.dut().timer_periodic &&
             fixture.dut().timer_interval == kTimerInterval,
         "Timer control outputs are incorrect");

  expect(fixture.write(soc::REG_DMA_SRC_ADDR, 0x11223344U) == soc::AXIL_RESP_OKAY,
         "DMA source write failed");
  expect(fixture.write(soc::REG_DMA_SRC_ADDR, 0xAABBCCDDU, 0x5U) ==
             soc::AXIL_RESP_OKAY,
         "DMA source partial write failed");
  expect_ok(fixture.read(soc::REG_DMA_SRC_ADDR, 3U), 0x11BB33DDU,
            "DMA source byte strobes are incorrect");
}

void test_errors(Fixture& fixture) {
  expect(fixture.write(soc::REG_SOC_ID, 0U) == soc::AXIL_RESP_SLVERR,
         "Read-only write did not fail");
  expect((fixture.read(soc::REG_ERROR_STATUS).data & bit(soc::ERR_READ_ONLY)) != 0U,
         "Read-only error was not recorded");
  clear_errors(fixture);

  const ReadResult illegal_read = fixture.read(kIllegalReadOffset);
  expect(illegal_read.response == soc::AXIL_RESP_SLVERR && illegal_read.data == 0U,
         "Illegal read behavior is incorrect");
  expect((fixture.read(soc::REG_ERROR_STATUS).data & bit(soc::ERR_ILLEGAL_MMIO)) != 0U,
         "Illegal read was not recorded");
  clear_errors(fixture);

  expect(fixture.write(kIllegalWriteOffset, 0xFFFFFFFFU) == soc::AXIL_RESP_SLVERR,
         "Illegal write did not fail");
  expect((fixture.read(soc::REG_ERROR_STATUS).data & bit(soc::ERR_ILLEGAL_MMIO)) != 0U,
         "Illegal write was not recorded");
  clear_errors(fixture);
}

void test_control_and_interrupts(Fixture& fixture) {
  const std::uint32_t control = bit(soc::CTRL_ENABLE_BIT) |
                                bit(soc::CTRL_PERF_CLEAR_BIT) |
                                bit(soc::CTRL_PRIORITY_POLICY_BIT);
  expect(fixture.begin_write(soc::REG_CTRL, control) == soc::AXIL_RESP_OKAY,
         "CTRL write failed");
  expect(fixture.dut().global_enable && fixture.dut().perf_clear &&
             fixture.dut().scheduler_priority_mode,
         "CTRL side effects are incorrect");
  fixture.complete_write();
  expect(!fixture.dut().perf_clear, "Performance-clear pulse did not self-clear");
  expect_ok(fixture.read(soc::REG_CTRL),
            bit(soc::CTRL_ENABLE_BIT) | bit(soc::CTRL_PRIORITY_POLICY_BIT),
            "CTRL pulse bit remained stored");

  const std::uint32_t scheduler_control =
      bit(soc::SCHED_POLICY_BIT) |
      (kSchedulerStarvationThreshold << soc::SCHED_STARVATION_LSB);
  expect(fixture.write(soc::REG_SCHED_CTRL, scheduler_control) ==
             soc::AXIL_RESP_OKAY,
         "Scheduler configuration write failed");
  expect(fixture.dut().scheduler_priority_mode &&
             fixture.dut().scheduler_starvation_threshold ==
                 kSchedulerStarvationThreshold,
         "Scheduler configuration outputs are incorrect");

  expect(fixture.write(soc::REG_SCHED_CTRL, 0U) == soc::AXIL_RESP_OKAY,
         "Scheduler control write failed");
  expect(!fixture.dut().scheduler_priority_mode &&
             fixture.dut().scheduler_starvation_threshold == 0U,
         "Scheduler configuration did not clear");
  expect((fixture.read(soc::REG_CTRL).data & bit(soc::CTRL_PRIORITY_POLICY_BIT)) == 0U,
         "CTRL scheduler mirror did not clear");

  fixture.dut().irq_pending = 0x15U;
  expect_ok(fixture.read(soc::REG_IRQ_STATUS), 0x15U, "IRQ pending read mismatch");
  expect(fixture.begin_write(soc::REG_IRQ_STATUS, 0x05U) == soc::AXIL_RESP_OKAY,
         "IRQ clear write failed");
  expect(fixture.dut().irq_clear == 0x05U, "IRQ clear pulse is incorrect");
  fixture.complete_write();
  expect(fixture.dut().irq_clear == 0U, "IRQ clear pulse did not self-clear");
  fixture.dut().irq_pending = 0U;
}

void test_dma_registers(Fixture& fixture) {
  auto& dut = fixture.dut();
  expect(fixture.write(soc::REG_DMA_SRC_ADDR, 0x80000100U) == soc::AXIL_RESP_OKAY,
         "DMA source configuration failed");
  expect(fixture.write(soc::REG_DMA_DST_ADDR, 0x10000200U) == soc::AXIL_RESP_OKAY,
         "DMA destination configuration failed");
  expect(fixture.write(soc::REG_DMA_LEN_BYTES, 0x00000120U) == soc::AXIL_RESP_OKAY,
         "DMA length configuration failed");

  const std::uint32_t dma_control =
      bit(soc::DMA_CTRL_START_BIT) | bit(soc::DMA_CTRL_IRQ_ENABLE_BIT);
  expect(fixture.begin_write(soc::REG_DMA_CTRL, dma_control) == soc::AXIL_RESP_OKAY,
         "DMA start write failed");
  expect(dut.dma_start && dut.dma_irq_enable && dut.dma_src_addr == 0x80000100U &&
             dut.dma_dst_addr == 0x10000200U && dut.dma_length_bytes == 0x120U,
         "DMA configuration outputs are incorrect");
  fixture.complete_write();
  expect(!dut.dma_start, "DMA start pulse did not self-clear");
  expect_ok(fixture.read(soc::REG_DMA_CTRL), bit(soc::DMA_CTRL_IRQ_ENABLE_BIT),
            "DMA start bit remained stored");

  dut.dma_busy = 1;
  expect(fixture.begin_write(soc::REG_DMA_CTRL, bit(soc::DMA_CTRL_START_BIT)) ==
             soc::AXIL_RESP_SLVERR,
         "DMA start while busy did not fail");
  expect(!dut.dma_start, "Rejected DMA start produced a pulse");
  fixture.complete_write();
  dut.dma_busy = 0;
  expect((fixture.read(soc::REG_ERROR_STATUS).data & bit(soc::ERR_DMA_BUSY)) != 0U,
         "DMA busy error was not recorded");
  clear_errors(fixture);

  dut.dma_done = 1;
  fixture.tick();
  dut.dma_done = 0;
  expect((fixture.read(soc::REG_DMA_STATUS).data & bit(soc::DMA_STATUS_DONE_BIT)) != 0U,
         "DMA done status did not latch");
  expect(fixture.write(soc::REG_DMA_STATUS, bit(soc::DMA_STATUS_DONE_BIT)) ==
             soc::AXIL_RESP_OKAY,
         "DMA done clear failed");
  expect((fixture.read(soc::REG_DMA_STATUS).data & bit(soc::DMA_STATUS_DONE_BIT)) == 0U,
         "DMA done status did not clear");

  dut.dma_error = 1;
  fixture.tick();
  dut.dma_error = 0;
  expect((fixture.read(soc::REG_DMA_STATUS).data & bit(soc::DMA_STATUS_ERROR_BIT)) != 0U,
         "DMA error status did not latch");
  expect((fixture.read(soc::REG_ERROR_STATUS).data & bit(soc::ERR_INTERNAL)) != 0U,
         "DMA error did not update global status");
  expect(fixture.write(soc::REG_DMA_STATUS, bit(soc::DMA_STATUS_ERROR_BIT)) ==
             soc::AXIL_RESP_OKAY,
         "DMA error clear failed");
  clear_errors(fixture);
}

void test_command_registers(Fixture& fixture) {
  auto& dut = fixture.dut();
  expect(fixture.write(soc::REG_CMD_OPCODE, soc::CMD_OP_VECTOR_ADD) ==
             soc::AXIL_RESP_OKAY,
         "Command opcode write failed");
  expect(fixture.write(soc::REG_CMD_SRC0_ADDR, 0x10000100U) == soc::AXIL_RESP_OKAY,
         "Command source zero write failed");
  expect(fixture.write(soc::REG_CMD_SRC1_ADDR, 0x10000200U) == soc::AXIL_RESP_OKAY,
         "Command source one write failed");
  expect(fixture.write(soc::REG_CMD_DST_ADDR, 0x10000300U) == soc::AXIL_RESP_OKAY,
         "Command destination write failed");
  expect(fixture.write(soc::REG_CMD_LEN, 17U) == soc::AXIL_RESP_OKAY,
         "Command length write failed");
  expect(fixture.write(soc::REG_CMD_M, 2U) == soc::AXIL_RESP_OKAY,
         "Command M write failed");
  expect(fixture.write(soc::REG_CMD_N, 3U) == soc::AXIL_RESP_OKAY,
         "Command N write failed");
  expect(fixture.write(soc::REG_CMD_K, 4U) == soc::AXIL_RESP_OKAY,
         "Command K write failed");
  expect(fixture.write(soc::REG_CMD_FLAGS, 0x5U) == soc::AXIL_RESP_OKAY,
         "Command flags write failed");
  expect(fixture.write(soc::REG_CMD_PRIORITY, 0x6U) == soc::AXIL_RESP_OKAY,
         "Command priority write failed");
  expect(fixture.write(soc::REG_CMD_ID, 0x1234U) == soc::AXIL_RESP_OKAY,
         "Command ID write failed");

  dut.cmd_ready = 0;
  dut.cmd_full = 0;
  expect(fixture.begin_write(soc::REG_CMD_SUBMIT, bit(soc::CMD_SUBMIT_BIT)) ==
             soc::AXIL_RESP_OKAY,
         "Command submit failed");
  expect(dut.cmd_valid && dut.cmd_opcode == soc::CMD_OP_VECTOR_ADD &&
             dut.cmd_src0_addr == 0x10000100U && dut.cmd_src1_addr == 0x10000200U &&
             dut.cmd_dst_addr == 0x10000300U && dut.cmd_length == 17U && dut.cmd_m == 2U &&
             dut.cmd_n == 3U && dut.cmd_k == 4U && dut.cmd_flags == 0x5U &&
             dut.cmd_priority == 0x6U && dut.cmd_id == 0x1234U,
         "Submitted command descriptor is incorrect");
  fixture.complete_write();
  fixture.tick();
  expect(dut.cmd_valid, "Command valid did not remain asserted under backpressure");
  dut.cmd_ready = 1;
  fixture.tick();
  dut.cmd_ready = 0;
  expect(!dut.cmd_valid, "Command valid did not clear after acceptance");

  dut.queue_full = 1;
  expect(fixture.write(soc::REG_CMD_SUBMIT, bit(soc::CMD_SUBMIT_BIT)) ==
             soc::AXIL_RESP_SLVERR,
         "Queue-full command submission did not fail");
  dut.queue_full = 0;
  expect((fixture.read(soc::REG_ERROR_STATUS).data & bit(soc::ERR_QUEUE_FULL)) != 0U,
         "Queue-full error was not recorded");
  clear_errors(fixture);

  dut.cmd_full = 1;
  expect(fixture.write(soc::REG_CMD_SUBMIT, bit(soc::CMD_SUBMIT_BIT)) ==
             soc::AXIL_RESP_SLVERR,
         "Command-interface-full submission did not fail");
  dut.cmd_full = 0;
  expect((fixture.read(soc::REG_ERROR_STATUS).data & bit(soc::ERR_QUEUE_FULL)) != 0U,
         "Command-interface-full error was not recorded");
  clear_errors(fixture);

  expect(fixture.write(soc::REG_CMD_OPCODE, soc::CMD_OP_INVALID) ==
             soc::AXIL_RESP_OKAY,
         "Invalid opcode staging write failed");
  expect(fixture.write(soc::REG_CMD_SUBMIT, bit(soc::CMD_SUBMIT_BIT)) ==
             soc::AXIL_RESP_SLVERR,
         "Invalid command opcode was accepted");
  expect((fixture.read(soc::REG_ERROR_STATUS).data & bit(soc::ERR_OPCODE)) != 0U,
         "Invalid opcode error was not recorded");
  clear_errors(fixture);

  dut.queue_occupancy = 3U;
  dut.queue_high_water = 7U;
  dut.queue_full = 1;
  dut.queue_empty = 0;
  const std::uint32_t expected_queue = (3U << soc::QUEUE_OCCUPANCY_LSB) |
                                       (7U << soc::QUEUE_HIGH_WATER_LSB) |
                                       bit(soc::QUEUE_FULL_BIT);
  expect_ok(fixture.read(soc::REG_QUEUE_STATUS), expected_queue,
            "Queue status encoding is incorrect");
  dut.queue_full = 0;
  dut.queue_empty = 1;
  dut.queue_occupancy = 0;

  dut.rsp_empty = 0;
  dut.rsp_valid = 1;
  dut.rsp_command_id = 0x1234U;
  dut.rsp_opcode = soc::CMD_OP_VECTOR_ADD;
  dut.rsp_error = soc::ERR_OPCODE;
  fixture.tick();
  dut.rsp_valid = 0;
  dut.rsp_empty = 1;
  const std::uint32_t command_status = fixture.read(soc::REG_CMD_STATUS).data;
  expect((command_status & bit(soc::CMD_STATUS_DONE_BIT)) != 0U &&
             (command_status & bit(soc::CMD_STATUS_ERROR_BIT)) != 0U,
         "Command completion status did not latch");
  expect(fixture.write(soc::REG_CMD_STATUS,
                       bit(soc::CMD_STATUS_DONE_BIT) | bit(soc::CMD_STATUS_ERROR_BIT)) ==
             soc::AXIL_RESP_OKAY,
         "Command status clear failed");
  expect((fixture.read(soc::REG_CMD_STATUS).data &
          (bit(soc::CMD_STATUS_DONE_BIT) | bit(soc::CMD_STATUS_ERROR_BIT))) == 0U,
         "Command completion status did not clear");
  clear_errors(fixture);
}

void test_performance_snapshot(Fixture& fixture) {
  auto& dut = fixture.dut();
  expect(fixture.write(soc::REG_PERF_SELECT, 9U) == soc::AXIL_RESP_OKAY,
         "Performance selector write failed");
  expect(dut.perf_select == 9U, "Performance selector output is incorrect");
  dut.perf_value = 0x1122334455667788ULL;
  expect_ok(fixture.read(soc::REG_PERF_VALUE), 0x55667788U,
            "Performance low word mismatch");
  dut.perf_value = 0xAABBCCDDEEFF0011ULL;
  expect_ok(fixture.read(soc::REG_PERF_VALUE_HI), 0x11223344U,
            "Performance high snapshot is incoherent");
}

void test_status_and_reset(Fixture& fixture) {
  auto& dut = fixture.dut();
  dut.soc_busy = 1;
  const std::uint32_t status = fixture.read(soc::REG_STATUS).data;
  expect((status & bit(soc::STATUS_READY_BIT)) != 0U &&
             (status & bit(soc::STATUS_BUSY_BIT)) != 0U,
         "Live SoC status is incorrect");
  dut.soc_busy = 0;

  dut.hardware_error_set = bit(soc::ERR_INTERNAL);
  fixture.tick();
  dut.hardware_error_set = 0;
  expect((fixture.read(soc::REG_ERROR_STATUS).data & bit(soc::ERR_INTERNAL)) != 0U,
         "Hardware error input did not latch");

  fixture.reset();
  expect(!dut.global_enable && !dut.perf_clear && !dut.dma_start && !dut.cmd_valid &&
             dut.error_status == 0U && dut.irq_enable == 0U,
         "Register block reset state is incorrect");
}

void test_random_registers(Fixture& fixture, std::mt19937& random) {
  constexpr std::array<std::uint32_t, 10> kRegisters = {
      soc::REG_DMA_SRC_ADDR, soc::REG_DMA_DST_ADDR, soc::REG_DMA_LEN_BYTES,
      soc::REG_CMD_SRC0_ADDR, soc::REG_CMD_SRC1_ADDR, soc::REG_CMD_DST_ADDR,
      soc::REG_CMD_LEN, soc::REG_CMD_M, soc::REG_CMD_N, soc::REG_CMD_K};
  std::array<std::uint32_t, kRegisters.size()> reference = {};

  fixture.reset();
  for (unsigned cycle = 0; cycle < kRandomRegisterCycles; ++cycle) {
    const std::size_t index = random() % kRegisters.size();
    const std::uint32_t data = random();
    const auto strobe =
        static_cast<std::uint8_t>((random() % kAllByteStrobes) + 1U);
    const auto order = static_cast<WriteOrder>(random() % 3U);
    const unsigned response_stall = random() % 3U;
    expect(fixture.write(kRegisters[index], data, strobe, order, response_stall) ==
               soc::AXIL_RESP_OKAY,
           "Random register write failed");
    reference[index] = apply_strobe(reference[index], data, strobe);
    const ReadResult result = fixture.read(kRegisters[index], random() % 3U);
    expect_ok(result, reference[index], "Random register readback mismatch");
  }
}

void run_directed(Fixture& fixture) {
  test_identity_and_bus(fixture);
  test_errors(fixture);
  test_control_and_interrupts(fixture);
  test_dma_registers(fixture);
  test_command_registers(fixture);
  test_performance_snapshot(fixture);
  test_status_and_reset(fixture);
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
    if (test_name == "regress") {
      std::mt19937 random(seed);
      test_random_registers(fixture, random);
    } else if (test_name != "smoke") {
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
