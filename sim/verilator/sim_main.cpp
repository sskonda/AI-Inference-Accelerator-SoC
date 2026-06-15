#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <optional>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include "Vsoc_top.h"
#include "cooperative_scheduler.hpp"
#include "gemm_model.hpp"
#include "mmio.hpp"
#include "reduction_model.hpp"
#include "sim_utils.hpp"
#include "soc_memory_map.hpp"
#include "soc_registers.hpp"
#include "vector_model.hpp"
#include "verilated.h"
#include "verilated_fst_c.h"

namespace {

constexpr std::uint32_t kDramInput0 = soc::DRAM_BASE_ADDR + 0x1000U;
constexpr std::uint32_t kDramInput1 = soc::DRAM_BASE_ADDR + 0x2000U;
constexpr std::uint32_t kDramOutput = soc::DRAM_BASE_ADDR + 0x3000U;
constexpr std::uint32_t kSpmSource0 = soc::SPM_BASE_ADDR;
constexpr std::uint32_t kSpmSource1 = soc::SPM_BASE_ADDR + 0x1000U;
constexpr std::uint32_t kSpmDestination = soc::SPM_BASE_ADDR + 0x2000U;
constexpr std::uint32_t kFirmwareDmaSource = soc::DRAM_BASE_ADDR + 0x10000U;
constexpr std::uint32_t kFirmwareDmaDestination =
    soc::DRAM_BASE_ADDR + 0x11000U;
constexpr std::uint32_t kFirmwareVectorSource0 =
    soc::DRAM_BASE_ADDR + 0x12000U;
constexpr std::uint32_t kFirmwareVectorSource1 =
    soc::DRAM_BASE_ADDR + 0x13000U;
constexpr std::uint32_t kFirmwareVectorDestination =
    soc::DRAM_BASE_ADDR + 0x14000U;
constexpr std::uint32_t kFirmwareReluSource =
    soc::DRAM_BASE_ADDR + 0x15000U;
constexpr std::uint32_t kFirmwareReluDestination =
    soc::DRAM_BASE_ADDR + 0x16000U;
constexpr std::uint32_t kFirmwareClampSource0 =
    soc::DRAM_BASE_ADDR + 0x17000U;
constexpr std::uint32_t kFirmwareClampSource1 =
    soc::DRAM_BASE_ADDR + 0x18000U;
constexpr std::uint32_t kFirmwareClampDestination =
    soc::DRAM_BASE_ADDR + 0x19000U;
constexpr std::uint32_t kFirmwareSumSource =
    soc::DRAM_BASE_ADDR + 0x1A000U;
constexpr std::uint32_t kFirmwareSumDestination =
    soc::DRAM_BASE_ADDR + 0x1B000U;
constexpr std::uint32_t kFirmwareMaxSource =
    soc::DRAM_BASE_ADDR + 0x1C000U;
constexpr std::uint32_t kFirmwareMaxDestination =
    soc::DRAM_BASE_ADDR + 0x1D000U;
constexpr std::uint32_t kFirmwareGemmSource0 =
    soc::DRAM_BASE_ADDR + 0x1E000U;
constexpr std::uint32_t kFirmwareGemmSource1 =
    soc::DRAM_BASE_ADDR + 0x1F000U;
constexpr std::uint32_t kFirmwareGemmDestination =
    soc::DRAM_BASE_ADDR + 0x20000U;
constexpr std::uint32_t kIllegalRegisterOffset = 0x0FCU;
constexpr std::uint32_t kDmaCommandId = 0x110U;
constexpr std::uint32_t kVectorCommandId = 0x120U;
constexpr std::uint32_t kReductionCommandId = 0x130U;
constexpr std::uint32_t kGemmCommandId = 0x140U;
constexpr std::uint32_t kLowPriority = 1U;
constexpr std::uint32_t kNormalPriority = 2U;
constexpr std::uint32_t kHighPriority = 3U;
constexpr unsigned kBitsPerByte = 8U;
constexpr unsigned kElementBytes = soc::ELEMENT_WIDTH / kBitsPerByte;
constexpr std::uint32_t kFullWriteStrobe =
    (std::uint32_t{1} << soc::DATA_BYTES) - 1U;
constexpr unsigned kTransactionTimeout = 2000U;
constexpr unsigned kOperationTimeout = 200000U;

void expect(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

std::uint32_t bit(unsigned index) {
  return std::uint32_t{1} << index;
}

std::size_t rounded_storage(std::size_t byte_count) {
  return ((byte_count + soc::DATA_BYTES - 1U) / soc::DATA_BYTES) *
         soc::DATA_BYTES;
}

struct PendingResponse {
  std::uint32_t data;
  bool error;
  unsigned delay;
};

class DramImage {
 public:
  DramImage() : bytes_(soc::DRAM_SIZE_BYTES, 0U) {}

  void fill(std::uint32_t address, std::size_t length, std::uint8_t value) {
    const auto offset = locate(address, length);
    std::fill(bytes_.begin() + static_cast<std::ptrdiff_t>(offset),
              bytes_.begin() + static_cast<std::ptrdiff_t>(offset + length),
              value);
  }

  void write_bytes(std::uint32_t address,
                   const std::vector<std::uint8_t>& values) {
    const auto offset = locate(address, values.size());
    std::copy(values.begin(), values.end(),
              bytes_.begin() + static_cast<std::ptrdiff_t>(offset));
  }

  std::vector<std::uint8_t> read_bytes(std::uint32_t address,
                                       std::size_t length) const {
    const auto offset = locate(address, length);
    return std::vector<std::uint8_t>(
        bytes_.begin() + static_cast<std::ptrdiff_t>(offset),
        bytes_.begin() + static_cast<std::ptrdiff_t>(offset + length));
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
        if ((strobe & bit(static_cast<unsigned>(byte_index))) != 0U) {
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
    if (address < soc::DRAM_BASE_ADDR) {
      throw std::out_of_range("address below external memory");
    }
    const auto offset =
        static_cast<std::size_t>(address - soc::DRAM_BASE_ADDR);
    if (offset > bytes_.size() || length > bytes_.size() - offset) {
      throw std::out_of_range("range outside external memory");
    }
    return offset;
  }

  std::vector<std::uint8_t> bytes_;
};

struct Command {
  std::uint32_t opcode;
  std::uint32_t source0;
  std::uint32_t source1;
  std::uint32_t destination;
  std::uint32_t length;
  std::uint32_t rows;
  std::uint32_t columns;
  std::uint32_t inner;
  std::uint32_t flags;
  std::uint32_t priority;
  std::uint32_t command_id;
};

class Fixture {
 public:
  explicit Fixture(std::uint32_t seed,
                   const std::optional<std::string>& trace_path)
      : ready_block_residue_(seed % kReadyBlockModulus),
        response_latency_(seed % 3U) {
    if (trace_path.has_value()) {
      trace_ = std::make_unique<VerilatedFstC>();
      dut_.trace(trace_.get(), kTraceDepth);
      trace_->open(trace_path->c_str());
    }
    clear_inputs();
    reset();
  }

  ~Fixture() {
    dut_.final();
    if (trace_) {
      trace_->close();
    }
  }

  Vsoc_top& dut() { return dut_; }
  DramImage& dram() { return dram_; }

  void evaluate() {
    dut_.eval();
    if (trace_) {
      const auto current_time = Verilated::time();
      if (!trace_has_dumped_ || (current_time != last_trace_time_)) {
        trace_->dump(current_time);
        last_trace_time_  = current_time;
        trace_has_dumped_ = true;
      }
    }
  }

  void tick() {
    prepare_memory_response();
    drive_memory_inputs();

    dut_.clk = 0;
    evaluate();
    Verilated::timeInc(1);

    const bool request_fire = dut_.memory_req_valid && dut_.memory_req_ready;
    const bool response_fire = dut_.memory_rsp_valid && dut_.memory_rsp_ready;
    const bool request_write = dut_.memory_req_write;
    const std::uint32_t request_address = dut_.memory_req_addr;
    const std::uint32_t request_data = dut_.memory_req_wdata;
    const std::uint32_t request_strobe = dut_.memory_req_wstrb;

    dut_.clk = 1;
    evaluate();
    Verilated::timeInc(1);

    dma_done_count_ += dut_.debug_dma_done;
    command_done_count_ += dut_.debug_command_completed;
    accelerator_done_count_ += dut_.debug_accelerator_done;
    irq_seen_ = irq_seen_ || dut_.irq;

    if (response_fire) {
      response_valid_ = false;
      response_data_ = 0U;
      response_error_ = false;
    }
    if (request_fire) {
      accept_memory_request(request_write, request_address, request_data,
                            request_strobe);
    }

    dut_.clk = 0;
    evaluate();
    Verilated::timeInc(1);
    ++cycle_;
  }

  void reset() {
    clear_bus_inputs();
    pending_response_.reset();
    response_valid_ = false;
    response_data_ = 0U;
    response_error_ = false;
    dma_done_count_ = 0U;
    command_done_count_ = 0U;
    accelerator_done_count_ = 0U;
    irq_seen_ = false;
    cycle_ = 0U;
    dut_.rst_n = 0;
    tick();
    tick();
    dut_.rst_n = 1;
    evaluate();
  }

  std::uint32_t mmio_write(std::uint32_t offset, std::uint32_t value,
                           std::uint32_t strobe = kFullWriteStrobe) {
    dut_.axil_awaddr = offset;
    dut_.axil_awvalid = 1;
    dut_.axil_wdata = value;
    dut_.axil_wstrb = strobe;
    dut_.axil_wvalid = 1;
    dut_.axil_bready = 1;

    bool address_done = false;
    bool data_done = false;
    for (unsigned wait_cycle = 0; wait_cycle < kTransactionTimeout;
         ++wait_cycle) {
      evaluate();
      const bool address_fire =
          !address_done && dut_.axil_awvalid && dut_.axil_awready;
      const bool data_fire =
          !data_done && dut_.axil_wvalid && dut_.axil_wready;
      tick();
      if (address_fire) {
        address_done = true;
        dut_.axil_awvalid = 0;
      }
      if (data_fire) {
        data_done = true;
        dut_.axil_wvalid = 0;
      }
      if (address_done && data_done && dut_.axil_bvalid) {
        const auto response = dut_.axil_bresp;
        tick();
        dut_.axil_bready = 0;
        evaluate();
        return response;
      }
    }
    throw std::runtime_error("AXI-Lite write timed out");
  }

  std::uint32_t mmio_read(std::uint32_t offset,
                          std::uint32_t* response_out = nullptr) {
    dut_.axil_araddr = offset;
    dut_.axil_arvalid = 1;
    dut_.axil_rready = 1;
    bool address_done = false;
    for (unsigned wait_cycle = 0; wait_cycle < kTransactionTimeout;
         ++wait_cycle) {
      evaluate();
      const bool address_fire =
          !address_done && dut_.axil_arvalid && dut_.axil_arready;
      tick();
      if (address_fire) {
        address_done = true;
        dut_.axil_arvalid = 0;
      }
      if (address_done && dut_.axil_rvalid) {
        const auto data = dut_.axil_rdata;
        const auto response = dut_.axil_rresp;
        tick();
        dut_.axil_rready = 0;
        evaluate();
        if (response_out != nullptr) {
          *response_out = response;
        }
        return data;
      }
    }
    throw std::runtime_error("AXI-Lite read timed out");
  }

  void run_mmio_dma(std::uint32_t source, std::uint32_t destination,
                    std::uint32_t length) {
    expect(mmio_write(soc::REG_DMA_STATUS,
                      bit(soc::DMA_STATUS_DONE_BIT) |
                          bit(soc::DMA_STATUS_ERROR_BIT)) ==
               soc::AXIL_RESP_OKAY,
           "DMA status clear failed");
    expect(mmio_write(soc::REG_DMA_SRC_ADDR, source) == soc::AXIL_RESP_OKAY,
           "DMA source programming failed");
    expect(mmio_write(soc::REG_DMA_DST_ADDR, destination) ==
               soc::AXIL_RESP_OKAY,
           "DMA destination programming failed");
    expect(mmio_write(soc::REG_DMA_LEN_BYTES, length) ==
               soc::AXIL_RESP_OKAY,
           "DMA length programming failed");
    expect(mmio_write(soc::REG_DMA_CTRL,
                      bit(soc::DMA_CTRL_START_BIT) |
                          bit(soc::DMA_CTRL_IRQ_ENABLE_BIT)) ==
               soc::AXIL_RESP_OKAY,
           "DMA start failed");

    for (unsigned wait_cycle = 0; wait_cycle < kOperationTimeout;
         ++wait_cycle) {
      const auto status = mmio_read(soc::REG_DMA_STATUS);
      if ((status & bit(soc::DMA_STATUS_DONE_BIT)) != 0U) {
        expect((status & bit(soc::DMA_STATUS_ERROR_BIT)) == 0U,
               "DMA completed with an error");
        wait_for_irq(bit(soc::IRQ_DMA_DONE_BIT));
        expect(mmio_write(soc::REG_IRQ_STATUS,
                          bit(soc::IRQ_DMA_DONE_BIT)) ==
                   soc::AXIL_RESP_OKAY,
               "DMA interrupt clear failed");
        return;
      }
    }
    throw std::runtime_error("DMA operation timed out");
  }

  void submit_command(const Command& command) {
    expect(mmio_write(soc::REG_CMD_STATUS,
                      bit(soc::CMD_STATUS_DONE_BIT) |
                          bit(soc::CMD_STATUS_ERROR_BIT)) ==
               soc::AXIL_RESP_OKAY,
           "command status clear failed");
    expect(mmio_write(soc::REG_CMD_OPCODE, command.opcode) ==
               soc::AXIL_RESP_OKAY,
           "command opcode programming failed");
    expect(mmio_write(soc::REG_CMD_SRC0_ADDR, command.source0) ==
               soc::AXIL_RESP_OKAY,
           "command source0 programming failed");
    expect(mmio_write(soc::REG_CMD_SRC1_ADDR, command.source1) ==
               soc::AXIL_RESP_OKAY,
           "command source1 programming failed");
    expect(mmio_write(soc::REG_CMD_DST_ADDR, command.destination) ==
               soc::AXIL_RESP_OKAY,
           "command destination programming failed");
    expect(mmio_write(soc::REG_CMD_LEN, command.length) ==
               soc::AXIL_RESP_OKAY,
           "command length programming failed");
    expect(mmio_write(soc::REG_CMD_M, command.rows) == soc::AXIL_RESP_OKAY,
           "command M programming failed");
    expect(mmio_write(soc::REG_CMD_N, command.columns) ==
               soc::AXIL_RESP_OKAY,
           "command N programming failed");
    expect(mmio_write(soc::REG_CMD_K, command.inner) == soc::AXIL_RESP_OKAY,
           "command K programming failed");
    expect(mmio_write(soc::REG_CMD_FLAGS, command.flags) ==
               soc::AXIL_RESP_OKAY,
           "command flags programming failed");
    expect(mmio_write(soc::REG_CMD_PRIORITY, command.priority) ==
               soc::AXIL_RESP_OKAY,
           "command priority programming failed");
    expect(mmio_write(soc::REG_CMD_ID, command.command_id) ==
               soc::AXIL_RESP_OKAY,
           "command ID programming failed");
    expect(mmio_write(soc::REG_CMD_SUBMIT, bit(soc::CMD_SUBMIT_BIT)) ==
               soc::AXIL_RESP_OKAY,
           "command submission failed");

    for (unsigned wait_cycle = 0; wait_cycle < kOperationTimeout;
         ++wait_cycle) {
      const auto status = mmio_read(soc::REG_CMD_STATUS);
      if ((status & bit(soc::CMD_STATUS_DONE_BIT)) != 0U) {
        expect((status & bit(soc::CMD_STATUS_ERROR_BIT)) == 0U,
               "accelerator command completed with an error");
        return;
      }
    }
    throw std::runtime_error("accelerator command timed out");
  }

  void wait_for_irq(std::uint32_t mask) {
    for (unsigned wait_cycle = 0; wait_cycle < kOperationTimeout;
         ++wait_cycle) {
      const auto pending = mmio_read(soc::REG_IRQ_STATUS);
      if ((pending & mask) == mask) {
        expect(dut_.irq, "enabled pending interrupt did not assert IRQ");
        return;
      }
    }
    throw std::runtime_error("interrupt did not become pending");
  }

  std::uint64_t read_performance_counter(std::uint32_t counter) {
    expect(mmio_write(soc::REG_PERF_SELECT, counter) ==
               soc::AXIL_RESP_OKAY,
           "performance counter selection failed");
    const auto low = mmio_read(soc::REG_PERF_VALUE);
    const auto high = mmio_read(soc::REG_PERF_VALUE_HI);
    return (static_cast<std::uint64_t>(high) << 32U) | low;
  }

  std::uint64_t dma_done_count() const { return dma_done_count_; }
  std::uint64_t command_done_count() const { return command_done_count_; }
  std::uint64_t accelerator_done_count() const {
    return accelerator_done_count_;
  }
  bool irq_seen() const { return irq_seen_; }

 private:
  static constexpr unsigned kReadyBlockModulus = 5U;
  static constexpr int kTraceDepth = 99;

  void prepare_memory_response() {
    if (response_valid_ || !pending_response_.has_value()) {
      return;
    }
    if (pending_response_->delay != 0U) {
      --pending_response_->delay;
      return;
    }
    response_valid_ = true;
    response_data_ = pending_response_->data;
    response_error_ = pending_response_->error;
    pending_response_.reset();
  }

  void drive_memory_inputs() {
    dut_.memory_req_ready =
        (cycle_ % kReadyBlockModulus) != ready_block_residue_;
    dut_.memory_rsp_valid = response_valid_ ? 1U : 0U;
    dut_.memory_rsp_rdata = response_data_;
    dut_.memory_rsp_error = response_error_ ? 1U : 0U;
  }

  void accept_memory_request(bool write, std::uint32_t address,
                             std::uint32_t data, std::uint32_t strobe) {
    expect(!response_valid_ && !pending_response_.has_value(),
           "external memory accepted multiple outstanding requests");
    expect((address % soc::DATA_BYTES) == 0U,
           "external memory request was not word aligned");

    bool legal = true;
    std::uint32_t response_data = 0U;
    if (write) {
      expect(strobe != 0U, "external memory write had no byte enables");
      legal = dram_.write_word(address, data, strobe);
    } else {
      expect(strobe == 0U, "external memory read used byte enables");
      legal = dram_.read_word(address, response_data);
    }
    pending_response_ =
        PendingResponse{response_data, !legal, response_latency_};
  }

  void clear_bus_inputs() {
    dut_.axil_awvalid = 0;
    dut_.axil_awaddr = 0U;
    dut_.axil_wvalid = 0;
    dut_.axil_wdata = 0U;
    dut_.axil_wstrb = 0U;
    dut_.axil_bready = 0;
    dut_.axil_arvalid = 0;
    dut_.axil_araddr = 0U;
    dut_.axil_rready = 0;
  }

  void clear_inputs() {
    dut_.clk = 0;
    dut_.rst_n = 0;
    clear_bus_inputs();
    dut_.memory_req_ready = 0;
    dut_.memory_rsp_valid = 0;
    dut_.memory_rsp_rdata = 0U;
    dut_.memory_rsp_error = 0;
  }

  Vsoc_top dut_;
  std::unique_ptr<VerilatedFstC> trace_;
  bool trace_has_dumped_ = false;
  std::uint64_t last_trace_time_ = 0U;
  DramImage dram_;
  std::optional<PendingResponse> pending_response_;
  bool response_valid_ = false;
  std::uint32_t response_data_ = 0U;
  bool response_error_ = false;
  unsigned ready_block_residue_;
  unsigned response_latency_;
  std::uint64_t cycle_ = 0U;
  std::uint64_t dma_done_count_ = 0U;
  std::uint64_t command_done_count_ = 0U;
  std::uint64_t accelerator_done_count_ = 0U;
  bool irq_seen_ = false;
};

class FixtureMmio final : public firmware::Mmio {
 public:
  explicit FixtureMmio(Fixture& fixture) : fixture_(fixture) {}

  std::uint32_t read(std::uint32_t offset) override {
    std::uint32_t response = 0U;
    const auto value = fixture_.mmio_read(offset, &response);
    if (response != soc::AXIL_RESP_OKAY) {
      throw std::runtime_error("firmware MMIO read failed");
    }
    return value;
  }

  void write(std::uint32_t offset, std::uint32_t value) override {
    if (fixture_.mmio_write(offset, value) != soc::AXIL_RESP_OKAY) {
      throw std::runtime_error("firmware MMIO write failed");
    }
  }

  bool irq_asserted() const override { return fixture_.dut().irq; }

 private:
  Fixture& fixture_;
};

void enable_soc_and_interrupts(Fixture& fixture) {
  expect(fixture.mmio_write(soc::REG_CTRL, bit(soc::CTRL_ENABLE_BIT)) ==
             soc::AXIL_RESP_OKAY,
         "SoC enable failed");
  const std::uint32_t interrupt_mask =
      bit(soc::IRQ_DMA_DONE_BIT) | bit(soc::IRQ_CMD_DONE_BIT) |
      bit(soc::IRQ_ACCEL_DONE_BIT) | bit(soc::IRQ_ERROR_BIT) |
      bit(soc::IRQ_TIMER_BIT);
  expect(fixture.mmio_write(soc::REG_IRQ_ENABLE, interrupt_mask) ==
             soc::AXIL_RESP_OKAY,
         "interrupt enable programming failed");
}

void test_reset_and_mmio(Fixture& fixture) {
  expect(!fixture.dut().soc_busy && !fixture.dut().irq &&
             fixture.dut().debug_queue_occupancy == 0U &&
             !fixture.dut().memory_req_valid,
         "reset did not return the SoC to idle");
  expect(fixture.dut().debug_definition_checksum != 0U,
         "definition checksum is unexpectedly zero");
  expect(fixture.mmio_read(soc::REG_SOC_ID) == soc::SOC_ID_VALUE,
         "SoC identity register mismatch");
  expect(fixture.mmio_read(soc::REG_VERSION) == soc::VERSION_VALUE,
         "SoC version register mismatch");
  std::uint32_t response = 0U;
  static_cast<void>(fixture.mmio_read(kIllegalRegisterOffset, &response));
  expect(response == soc::AXIL_RESP_SLVERR,
         "illegal MMIO read did not return an error");
  expect(fixture.mmio_write(soc::REG_ERROR_STATUS,
                            bit(soc::ERR_ILLEGAL_MMIO)) ==
             soc::AXIL_RESP_OKAY,
         "error status clear failed");
  enable_soc_and_interrupts(fixture);
}

void test_mmio_dma(Fixture& fixture) {
  std::vector<std::uint8_t> source(19U);
  for (std::size_t index = 0; index < source.size(); ++index) {
    source[index] = static_cast<std::uint8_t>(index * 17U + 3U);
  }
  fixture.dram().write_bytes(kDramInput0, source);
  fixture.dram().fill(kDramOutput, source.size(), 0xA5U);
  fixture.run_mmio_dma(kDramInput0, kSpmSource0,
                       static_cast<std::uint32_t>(source.size()));
  fixture.run_mmio_dma(kSpmSource0, kDramOutput,
                       static_cast<std::uint32_t>(source.size()));
  expect(fixture.dram().read_bytes(kDramOutput, source.size()) == source,
         "SoC DMA round trip corrupted data");
}

void test_queued_dma(Fixture& fixture) {
  std::vector<std::uint8_t> source(20U);
  for (std::size_t index = 0; index < source.size(); ++index) {
    source[index] = static_cast<std::uint8_t>(0xF0U - index);
  }
  fixture.dram().write_bytes(kDramInput0, source);
  fixture.submit_command(
      Command{soc::CMD_OP_DMA_COPY, kDramInput0, 0U, kSpmSource0,
              static_cast<std::uint32_t>(source.size()), 0U, 0U, 0U, 0U,
              kNormalPriority, kDmaCommandId});
  fixture.wait_for_irq(bit(soc::IRQ_CMD_DONE_BIT));
  expect(fixture.mmio_write(soc::REG_IRQ_STATUS,
                            bit(soc::IRQ_CMD_DONE_BIT) |
                                bit(soc::IRQ_DMA_DONE_BIT)) ==
             soc::AXIL_RESP_OKAY,
         "command interrupt clear failed");
  fixture.run_mmio_dma(kSpmSource0, kDramOutput,
                       static_cast<std::uint32_t>(source.size()));
  expect(fixture.dram().read_bytes(kDramOutput, source.size()) == source,
         "queued DMA command corrupted data");
}

void test_vector(Fixture& fixture) {
  const std::vector<std::uint16_t> source0 = {
      1U, 2U, 3U, 4U, 0xFFFFU, 30000U, 7U};
  const std::vector<std::uint16_t> source1 = {
      8U, 7U, 6U, 5U, 2U, 10000U, 9U};
  const auto byte_count = source0.size() * kElementBytes;
  const auto storage_bytes = rounded_storage(byte_count);
  fixture.dram().fill(kDramInput0, storage_bytes, 0U);
  fixture.dram().fill(kDramInput1, storage_bytes, 0U);
  fixture.dram().write_elements(kDramInput0, source0);
  fixture.dram().write_elements(kDramInput1, source1);
  fixture.run_mmio_dma(kDramInput0, kSpmSource0,
                       static_cast<std::uint32_t>(storage_bytes));
  fixture.run_mmio_dma(kDramInput1, kSpmSource1,
                       static_cast<std::uint32_t>(storage_bytes));

  fixture.submit_command(
      Command{soc::CMD_OP_VECTOR_ADD, kSpmSource0, kSpmSource1,
              kSpmDestination, static_cast<std::uint32_t>(source0.size()),
              0U, 0U, 0U, bit(soc::FLAG_SATURATE_BIT), kHighPriority,
              kVectorCommandId});
  fixture.wait_for_irq(bit(soc::IRQ_CMD_DONE_BIT) |
                       bit(soc::IRQ_ACCEL_DONE_BIT));
  expect(fixture.mmio_write(soc::REG_IRQ_STATUS,
                            bit(soc::IRQ_CMD_DONE_BIT) |
                                bit(soc::IRQ_ACCEL_DONE_BIT)) ==
             soc::AXIL_RESP_OKAY,
         "vector interrupt clear failed");

  fixture.run_mmio_dma(kSpmDestination, kDramOutput,
                       static_cast<std::uint32_t>(byte_count));
  const auto expected = model::vector_operation(
      soc::CMD_OP_VECTOR_ADD, source0, source1, 0U, false, true);
  expect(fixture.dram().read_elements(kDramOutput, expected.size()) ==
             expected,
         "SoC vector result mismatch");
}

void test_reduction(Fixture& fixture) {
  const std::vector<std::uint16_t> source = {
      static_cast<std::uint16_t>(-4), 7U,
      static_cast<std::uint16_t>(-2), 3U, 8U};
  const auto byte_count = source.size() * kElementBytes;
  const auto storage_bytes = rounded_storage(byte_count);
  fixture.dram().fill(kDramInput0, storage_bytes, 0U);
  fixture.dram().write_elements(kDramInput0, source);
  fixture.run_mmio_dma(kDramInput0, kSpmSource0,
                       static_cast<std::uint32_t>(storage_bytes));
  fixture.submit_command(
      Command{soc::CMD_OP_REDUCE_SUM, kSpmSource0, 0U, kSpmDestination,
              static_cast<std::uint32_t>(source.size()), 0U, 0U, 0U,
              bit(soc::FLAG_SIGNED_BIT), kLowPriority,
              kReductionCommandId});
  fixture.wait_for_irq(bit(soc::IRQ_CMD_DONE_BIT) |
                       bit(soc::IRQ_ACCEL_DONE_BIT));
  expect(fixture.mmio_write(soc::REG_IRQ_STATUS,
                            bit(soc::IRQ_CMD_DONE_BIT) |
                                bit(soc::IRQ_ACCEL_DONE_BIT)) ==
             soc::AXIL_RESP_OKAY,
         "reduction interrupt clear failed");
  fixture.run_mmio_dma(kSpmDestination, kDramOutput, kElementBytes);
  const auto expected =
      model::reduction_operation(soc::CMD_OP_REDUCE_SUM, source, true, false);
  expect(fixture.dram().read_elements(kDramOutput, 1U).front() == expected,
         "SoC reduction result mismatch");
}

void test_gemm(Fixture& fixture) {
  constexpr std::uint32_t kRows = 3U;
  constexpr std::uint32_t kColumns = 4U;
  constexpr std::uint32_t kInner = 2U;
  const std::vector<std::uint16_t> matrix_a = {
      1U, 2U, 3U, 4U, 5U, 6U};
  const std::vector<std::uint16_t> matrix_b = {
      1U, 2U, 3U, 4U, 5U, 6U, 7U, 8U};
  const auto a_bytes = matrix_a.size() * kElementBytes;
  const auto b_bytes = matrix_b.size() * kElementBytes;
  const auto output_count =
      static_cast<std::size_t>(kRows) * static_cast<std::size_t>(kColumns);
  const auto output_bytes = output_count * kElementBytes;
  fixture.dram().write_elements(kDramInput0, matrix_a);
  fixture.dram().write_elements(kDramInput1, matrix_b);
  fixture.run_mmio_dma(kDramInput0, kSpmSource0,
                       static_cast<std::uint32_t>(a_bytes));
  fixture.run_mmio_dma(kDramInput1, kSpmSource1,
                       static_cast<std::uint32_t>(b_bytes));
  fixture.submit_command(
      Command{soc::CMD_OP_GEMM, kSpmSource0, kSpmSource1, kSpmDestination,
              0U, kRows, kColumns, kInner, 0U, kHighPriority,
              kGemmCommandId});
  fixture.wait_for_irq(bit(soc::IRQ_CMD_DONE_BIT) |
                       bit(soc::IRQ_ACCEL_DONE_BIT));
  expect(fixture.mmio_write(soc::REG_IRQ_STATUS,
                            bit(soc::IRQ_CMD_DONE_BIT) |
                                bit(soc::IRQ_ACCEL_DONE_BIT)) ==
             soc::AXIL_RESP_OKAY,
         "GEMM interrupt clear failed");
  fixture.run_mmio_dma(kSpmDestination, kDramOutput,
                       static_cast<std::uint32_t>(output_bytes));
  const auto expected = model::gemm_operation(
      matrix_a, matrix_b, kRows, kColumns, kInner, false, false);
  expect(fixture.dram().read_elements(kDramOutput, output_count) == expected,
         "SoC GEMM result mismatch");
}

void test_firmware_scheduler(Fixture& fixture) {
  const std::vector<std::uint8_t> dma_source = {
      0x11U, 0x22U, 0x33U, 0x44U, 0x55U, 0x66U, 0x77U,
      0x88U, 0x99U, 0xAAU, 0xBBU, 0xCCU, 0xDDU};
  const std::vector<std::uint16_t> vector_source0 = {
      1U, 4U, 9U, 16U, 100U, 40000U};
  const std::vector<std::uint16_t> vector_source1 = {
      2U, 3U, 5U, 7U, 500U, 30000U};
  const std::vector<std::uint16_t> relu_source = {
      static_cast<std::uint16_t>(-8), 0U, 7U,
      static_cast<std::uint16_t>(-1), 12U};
  const std::vector<std::uint16_t> clamp_source0 = {
      1U, 9U, 4U, 20U, 6U};
  const std::vector<std::uint16_t> clamp_source1 = {
      3U, 5U, 8U, 10U, 6U};
  const std::vector<std::uint16_t> sum_source = {
      static_cast<std::uint16_t>(-3), 7U, 11U,
      static_cast<std::uint16_t>(-2), 4U};
  const std::vector<std::uint16_t> max_source = {
      3U, 99U, 12U, 44U, 8U, 71U};
  constexpr std::uint32_t kGemmRows = 2U;
  constexpr std::uint32_t kGemmColumns = 2U;
  constexpr std::uint32_t kGemmInner = 3U;
  const std::vector<std::uint16_t> gemm_source0 = {
      1U, 2U, 3U, 4U, 5U, 6U};
  const std::vector<std::uint16_t> gemm_source1 = {
      7U, 8U, 9U, 10U, 11U, 12U};

  fixture.dram().write_bytes(kFirmwareDmaSource, dma_source);
  fixture.dram().write_elements(kFirmwareVectorSource0, vector_source0);
  fixture.dram().write_elements(kFirmwareVectorSource1, vector_source1);
  fixture.dram().write_elements(kFirmwareReluSource, relu_source);
  fixture.dram().write_elements(kFirmwareClampSource0, clamp_source0);
  fixture.dram().write_elements(kFirmwareClampSource1, clamp_source1);
  fixture.dram().write_elements(kFirmwareSumSource, sum_source);
  fixture.dram().write_elements(kFirmwareMaxSource, max_source);
  fixture.dram().write_elements(kFirmwareGemmSource0, gemm_source0);
  fixture.dram().write_elements(kFirmwareGemmSource1, gemm_source1);

  FixtureMmio mmio(fixture);
  firmware::CooperativeScheduler scheduler(mmio);
  scheduler.boot();
  const auto dma_task = scheduler.submit_dma_copy(
      kFirmwareDmaSource, kFirmwareDmaDestination,
      static_cast<std::uint32_t>(dma_source.size()), 1U);
  const auto vector_task = scheduler.submit_vector_add(
      kFirmwareVectorSource0, kFirmwareVectorSource1,
      kFirmwareVectorDestination,
      static_cast<std::uint32_t>(vector_source0.size()), 6U, false, true);
  const auto relu_task = scheduler.submit_vector_relu_or_clamp(
      kFirmwareReluSource, 0U, kFirmwareReluDestination,
      static_cast<std::uint32_t>(relu_source.size()), false, 3U, true);
  const auto clamp_task = scheduler.submit_vector_relu_or_clamp(
      kFirmwareClampSource0, kFirmwareClampSource1,
      kFirmwareClampDestination,
      static_cast<std::uint32_t>(clamp_source0.size()), true, 4U, false);
  const auto sum_task = scheduler.submit_reduce_sum(
      kFirmwareSumSource, kFirmwareSumDestination,
      static_cast<std::uint32_t>(sum_source.size()), 5U, true, true);
  const auto max_task = scheduler.submit_reduce_max(
      kFirmwareMaxSource, kFirmwareMaxDestination,
      static_cast<std::uint32_t>(max_source.size()), 2U);
  const auto gemm_task = scheduler.submit_gemm(
      kFirmwareGemmSource0, kFirmwareGemmSource1,
      kFirmwareGemmDestination, kGemmRows, kGemmColumns, kGemmInner, 7U);

  for (unsigned iteration = 0;
       iteration < kOperationTimeout && !scheduler.all_tasks_terminal();
       ++iteration) {
    scheduler.run_once();
    fixture.tick();
  }

  expect(scheduler.all_tasks_terminal(),
         "firmware scheduler did not complete the mixed workload");
  for (const auto& task : scheduler.tasks()) {
    expect(task.state == firmware::TaskState::DONE,
           "firmware task completed in an error state");
  }
  expect(!scheduler.dispatch_order().empty() &&
             scheduler.dispatch_order().front() == gemm_task,
         "firmware scheduler did not dispatch the highest-priority task first");
  expect(scheduler.completion_order().size() == scheduler.tasks().size(),
         "firmware scheduler lost a task completion");

  expect(fixture.dram().read_bytes(kFirmwareDmaDestination,
                                   dma_source.size()) == dma_source,
         "firmware DMA workload mismatch");
  const auto vector_expected = model::vector_operation(
      soc::CMD_OP_VECTOR_ADD, vector_source0, vector_source1, 0U, false,
      true);
  expect(fixture.dram().read_elements(kFirmwareVectorDestination,
                                      vector_expected.size()) ==
             vector_expected,
         "firmware vector add mismatch");
  const auto relu_expected = model::vector_operation(
      soc::CMD_OP_VECTOR_RELU, relu_source, {}, 0U, true, false);
  expect(fixture.dram().read_elements(kFirmwareReluDestination,
                                      relu_expected.size()) == relu_expected,
         "firmware ReLU mismatch");
  const auto clamp_expected = model::vector_operation(
      soc::CMD_OP_VECTOR_CLAMP, clamp_source0, clamp_source1, 0U, false,
      false);
  expect(fixture.dram().read_elements(kFirmwareClampDestination,
                                      clamp_expected.size()) ==
             clamp_expected,
         "firmware clamp mismatch");
  const auto sum_expected = model::reduction_operation(
      soc::CMD_OP_REDUCE_SUM, sum_source, true, true);
  expect(fixture.dram().read_elements(kFirmwareSumDestination, 1U).front() ==
             sum_expected,
         "firmware reduction sum mismatch");
  const auto max_expected = model::reduction_operation(
      soc::CMD_OP_REDUCE_MAX, max_source, false, false);
  expect(fixture.dram().read_elements(kFirmwareMaxDestination, 1U).front() ==
             max_expected,
         "firmware reduction max mismatch");
  const auto gemm_expected = model::gemm_operation(
      gemm_source0, gemm_source1, kGemmRows, kGemmColumns, kGemmInner,
      false, false);
  expect(fixture.dram().read_elements(kFirmwareGemmDestination,
                                      gemm_expected.size()) ==
             gemm_expected,
         "firmware GEMM mismatch");

  const auto performance = scheduler.performance_snapshot();
  expect(performance.total_cycles != 0U &&
             performance.commands_completed >= 6U &&
             performance.bytes_read != 0U &&
             performance.bytes_written != 0U &&
             performance.queue_high_water != 0U,
         "firmware performance log is incomplete");
  expect(scheduler.software_scheduler_stalls() != 0U,
         "firmware scheduler did not record blocked intervals");
  expect(scheduler.tasks().at(dma_task).completed_at != 0U &&
             scheduler.tasks().at(vector_task).completed_at != 0U &&
             scheduler.tasks().at(relu_task).completed_at != 0U &&
             scheduler.tasks().at(clamp_task).completed_at != 0U &&
             scheduler.tasks().at(sum_task).completed_at != 0U &&
             scheduler.tasks().at(max_task).completed_at != 0U,
         "firmware task timing log is incomplete");
}

void test_timer_and_performance(Fixture& fixture) {
  constexpr std::uint32_t kTimerInterval = 6U;
  const auto timer_control =
      bit(soc::TIMER_ENABLE_BIT) | bit(soc::TIMER_PERIODIC_BIT) |
      (kTimerInterval << soc::TIMER_INTERVAL_LSB);
  expect(fixture.mmio_write(soc::REG_TIMER_CTRL, timer_control) ==
             soc::AXIL_RESP_OKAY,
         "timer programming failed");
  fixture.wait_for_irq(bit(soc::IRQ_TIMER_BIT));
  expect(fixture.mmio_write(soc::REG_IRQ_STATUS,
                            bit(soc::IRQ_TIMER_BIT)) ==
             soc::AXIL_RESP_OKAY,
         "timer interrupt clear failed");
  expect(fixture.mmio_write(soc::REG_TIMER_CTRL, 0U) ==
             soc::AXIL_RESP_OKAY,
         "timer disable failed");

  expect(fixture.read_performance_counter(soc::PERF_TOTAL_CYCLES) != 0U,
         "total-cycle counter did not advance");
  expect(fixture.read_performance_counter(soc::PERF_BYTES_READ) != 0U &&
             fixture.read_performance_counter(soc::PERF_BYTES_WRITTEN) != 0U,
         "DMA byte counters did not advance");
  expect(fixture.read_performance_counter(soc::PERF_COMMANDS_COMPLETED) >=
             4U,
         "command completion counter is too small");
  expect(fixture.read_performance_counter(soc::PERF_QUEUE_HIGH_WATER) >= 1U,
         "queue high-water counter did not observe a command");
  expect(fixture.dut().debug_error_status == 0U,
         "unexpected hardware error remained after legal workloads");
  expect(fixture.dma_done_count() >= 10U &&
             fixture.command_done_count() >= 4U &&
             fixture.accelerator_done_count() >= 3U &&
             fixture.irq_seen(),
         "expected completion and interrupt events were not observed");
}

struct Options {
  std::uint32_t seed = 1U;
  std::string test_name = "smoke";
  std::optional<std::string> trace_path;
};

Options parse_options(int argc, char** argv) {
  Options options;
  for (int index = 1; index < argc; ++index) {
    const std::string argument = argv[index];
    if ((argument == "--seed") && (index + 1 < argc)) {
      options.seed = static_cast<std::uint32_t>(std::stoul(argv[++index]));
    } else if ((argument == "--test") && (index + 1 < argc)) {
      options.test_name = argv[++index];
    } else if ((argument == "--trace") && (index + 1 < argc)) {
      options.trace_path = argv[++index];
    } else if (argument == sim::kCoverageFileOption && (index + 1 < argc)) {
      ++index;
    }
  }
  return options;
}

void print_mixed_performance(Fixture& fixture, std::uint32_t seed) {
  const auto total_cycles =
      fixture.read_performance_counter(soc::PERF_TOTAL_CYCLES);
  const auto dma_active =
      fixture.read_performance_counter(soc::PERF_DMA_ACTIVE_CYCLES);
  const auto dma_stalled =
      fixture.read_performance_counter(soc::PERF_DMA_STALLED_CYCLES);
  const auto accelerator_active =
      fixture.read_performance_counter(soc::PERF_ACCEL_ACTIVE_CYCLES);
  const auto accelerator_stalled =
      fixture.read_performance_counter(soc::PERF_ACCEL_STALLED_CYCLES);
  const auto queue_high_water =
      fixture.read_performance_counter(soc::PERF_QUEUE_HIGH_WATER);
  const auto commands_completed =
      fixture.read_performance_counter(soc::PERF_COMMANDS_COMPLETED);
  const auto bytes_read =
      fixture.read_performance_counter(soc::PERF_BYTES_READ);
  const auto bytes_written =
      fixture.read_performance_counter(soc::PERF_BYTES_WRITTEN);
  const auto interrupt_latency =
      fixture.read_performance_counter(soc::PERF_IRQ_LATENCY);
  const auto scheduler_stalls =
      fixture.read_performance_counter(soc::PERF_SCHEDULER_STALLS);

  std::cout << "PERF suite=soc workload=mixed_firmware"
            << " seed=" << seed
            << " total_cycles=" << total_cycles
            << " dma_active_cycles=" << dma_active
            << " dma_stalled_cycles=" << dma_stalled
            << " accelerator_active_cycles=" << accelerator_active
            << " accelerator_stalled_cycles=" << accelerator_stalled
            << " queue_high_water=" << queue_high_water
            << " commands_completed=" << commands_completed
            << " bytes_read=" << bytes_read
            << " bytes_written=" << bytes_written
            << " interrupt_latency=" << interrupt_latency
            << " scheduler_stalls=" << scheduler_stalls
            << " dma_done_events=" << fixture.dma_done_count()
            << " command_done_events=" << fixture.command_done_count()
            << " accelerator_done_events=" << fixture.accelerator_done_count()
            << " irq_seen=" << (fixture.irq_seen() ? 1U : 0U) << '\n';
}

}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  const auto options = parse_options(argc, argv);
  if (options.trace_path.has_value()) {
    Verilated::traceEverOn(true);
  }

  try {
    if (options.test_name != "smoke" && options.test_name != "regress" &&
        options.test_name != "perf") {
      throw std::runtime_error("unsupported test name: " + options.test_name);
    }
    Fixture fixture(options.seed, options.trace_path);
    test_reset_and_mmio(fixture);
    test_mmio_dma(fixture);
    test_queued_dma(fixture);
    test_vector(fixture);
    test_reduction(fixture);
    test_gemm(fixture);
    test_firmware_scheduler(fixture);
    test_timer_and_performance(fixture);
    if (options.test_name == "perf") {
      print_mixed_performance(fixture, options.seed);
    }
    sim::write_coverage_if_requested(argc, argv);
    std::cout << "PASS test=soc seed=" << options.seed << '\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL test=soc seed=" << options.seed
              << " reason=" << error.what() << '\n';
    return 1;
  }
}
