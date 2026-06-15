#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>

#include "cooperative_scheduler.hpp"
#include "hardware_drivers.hpp"
#include "soc_memory_map.hpp"
#include "soc_registers.hpp"

namespace {

constexpr std::size_t kRegisterWords = 64U;
constexpr std::uint32_t kSource0 = soc::DRAM_BASE_ADDR + 0x1000U;
constexpr std::uint32_t kSource1 = soc::DRAM_BASE_ADDR + 0x2000U;
constexpr std::uint32_t kDestination = soc::DRAM_BASE_ADDR + 0x3000U;
constexpr std::uint32_t kPriorityLow = 1U;
constexpr std::uint32_t kPriorityHigh = 4U;
constexpr std::uint32_t kDriverTransferBytes = 37U;
constexpr std::uint32_t kTestCommandId = 0x44U;

void expect(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

class FakeMmio final : public firmware::Mmio {
 public:
  std::uint32_t read(std::uint32_t offset) override {
    if (offset == soc::REG_IRQ_STATUS) {
      return irq_pending_;
    }
    return registers_.at(index(offset));
  }

  void write(std::uint32_t offset, std::uint32_t value) override {
    if (offset == soc::REG_IRQ_STATUS) {
      irq_pending_ &= ~value;
      return;
    }
    if (offset == soc::REG_DMA_STATUS) {
      registers_.at(index(offset)) &= ~value;
      return;
    }
    if (offset == soc::REG_CMD_STATUS) {
      registers_.at(index(offset)) &= ~value;
      return;
    }
    registers_.at(index(offset)) = value;
    if (offset == soc::REG_DMA_CTRL &&
        (value & firmware::register_bit(soc::DMA_CTRL_START_BIT)) != 0U) {
      registers_.at(index(soc::REG_DMA_STATUS)) =
          firmware::register_bit(soc::DMA_STATUS_BUSY_BIT);
    }
    if (offset == soc::REG_CMD_SUBMIT &&
        (value & firmware::register_bit(soc::CMD_SUBMIT_BIT)) != 0U) {
      registers_.at(index(soc::REG_CMD_STATUS)) =
          firmware::register_bit(soc::CMD_STATUS_PENDING_BIT);
    }
  }

  bool irq_asserted() const override {
    const auto enabled = registers_.at(index(soc::REG_IRQ_ENABLE));
    return (irq_pending_ & enabled) != 0U;
  }

  void complete_dma(bool error = false) {
    registers_.at(index(soc::REG_DMA_STATUS)) =
        firmware::register_bit(soc::DMA_STATUS_DONE_BIT) |
        (error ? firmware::register_bit(soc::DMA_STATUS_ERROR_BIT) : 0U);
    irq_pending_ |= firmware::register_bit(soc::IRQ_DMA_DONE_BIT);
  }

  void complete_accelerator(bool error = false) {
    registers_.at(index(soc::REG_CMD_STATUS)) =
        firmware::register_bit(soc::CMD_STATUS_DONE_BIT) |
        (error ? firmware::register_bit(soc::CMD_STATUS_ERROR_BIT) : 0U);
    irq_pending_ |= firmware::register_bit(soc::IRQ_CMD_DONE_BIT) |
                    firmware::register_bit(soc::IRQ_ACCEL_DONE_BIT);
  }

  std::uint32_t register_value(std::uint32_t offset) const {
    return registers_.at(index(offset));
  }

 private:
  static std::size_t index(std::uint32_t offset) {
    if ((offset % soc::DATA_BYTES) != 0U) {
      throw std::out_of_range("unaligned fake MMIO access");
    }
    return static_cast<std::size_t>(offset / soc::DATA_BYTES);
  }

  std::array<std::uint32_t, kRegisterWords> registers_{};
  std::uint32_t irq_pending_ = 0U;
};

void test_drivers() {
  FakeMmio mmio;
  firmware::DmaDriver dma(mmio);
  dma.start(kSource0, kDestination, kDriverTransferBytes);
  expect(mmio.register_value(soc::REG_DMA_SRC_ADDR) == kSource0,
         "DMA driver source mismatch");
  expect(mmio.register_value(soc::REG_DMA_DST_ADDR) == kDestination,
         "DMA driver destination mismatch");
  expect(mmio.register_value(soc::REG_DMA_LEN_BYTES) ==
             kDriverTransferBytes,
         "DMA driver length mismatch");
  expect(dma.status().busy, "DMA driver did not observe busy status");

  FakeMmio command_mmio;
  firmware::AcceleratorDriver accelerator(command_mmio);
  accelerator.submit(
      firmware::CommandDescriptor{soc::CMD_OP_VECTOR_ADD, kSource0, kSource1,
                                  kDestination, 8U, 0U, 0U, 0U, 0U,
                                  kPriorityHigh, kTestCommandId});
  expect(command_mmio.register_value(soc::REG_CMD_OPCODE) ==
             soc::CMD_OP_VECTOR_ADD,
         "accelerator opcode mismatch");
  expect(command_mmio.register_value(soc::REG_CMD_ID) == kTestCommandId,
         "accelerator command ID mismatch");
  expect(accelerator.status().busy,
         "accelerator driver did not observe pending command");
}

void test_scheduler_interrupt_flow() {
  FakeMmio mmio;
  firmware::CooperativeScheduler scheduler(mmio);
  scheduler.boot();
  const auto low_task = scheduler.submit_dma_copy(
      kSource0, kDestination, 32U, kPriorityLow);
  const auto high_task = scheduler.submit_vector_add(
      kSource0, kSource1, kDestination, 8U, kPriorityHigh);

  scheduler.run_once();
  expect(scheduler.tasks().at(high_task).state ==
             firmware::TaskState::BLOCKED_ON_DMA,
         "high-priority task did not start first");

  mmio.complete_dma();
  scheduler.run_once();
  expect(scheduler.tasks().at(high_task).phase ==
             firmware::TaskPhase::LOAD_SOURCE1,
         "source0 completion did not advance the vector task");

  mmio.complete_dma();
  scheduler.run_once();
  expect(scheduler.tasks().at(high_task).state ==
             firmware::TaskState::BLOCKED_ON_ACCEL,
         "vector task did not block on the accelerator");

  mmio.complete_accelerator();
  scheduler.run_once();
  expect(scheduler.tasks().at(high_task).state ==
             firmware::TaskState::BLOCKED_ON_DMA,
         "vector task did not start result writeback");

  mmio.complete_dma();
  scheduler.run_once();
  expect(scheduler.tasks().at(high_task).state == firmware::TaskState::DONE,
         "vector task did not complete");
  expect(scheduler.tasks().at(low_task).state ==
             firmware::TaskState::BLOCKED_ON_DMA,
         "lower-priority DMA task did not run after vector completion");

  mmio.complete_dma();
  scheduler.run_once();
  expect(scheduler.all_tasks_terminal(), "scheduler left tasks runnable");
  expect(scheduler.completion_order().size() == 2U &&
             scheduler.completion_order().front() == high_task &&
             scheduler.completion_order().back() == low_task,
         "task completion order did not preserve priority");
}

void test_scheduler_error_flow() {
  FakeMmio mmio;
  firmware::CooperativeScheduler scheduler(mmio);
  scheduler.boot();
  const auto task = scheduler.submit_dma_copy(
      kSource0, kDestination, 16U, kPriorityLow);
  scheduler.run_once();
  mmio.complete_dma(true);
  scheduler.run_once();
  expect(scheduler.tasks().at(task).state == firmware::TaskState::ERROR,
         "DMA failure did not terminate the owning task");
  expect(!scheduler.tasks().at(task).error_message.empty(),
         "failed task did not record an error reason");
  expect(scheduler.all_tasks_terminal(),
         "failed task was not considered terminal");
}

void test_submission_apis() {
  FakeMmio mmio;
  firmware::CooperativeScheduler scheduler(mmio);
  scheduler.submit_vector_relu_or_clamp(
      kSource0, 0U, kDestination, 4U, false, kPriorityLow);
  scheduler.submit_vector_relu_or_clamp(
      kSource0, kSource1, kDestination, 4U, true, kPriorityLow);
  scheduler.submit_reduce_sum(
      kSource0, kDestination, 4U, kPriorityLow, true, true);
  scheduler.submit_reduce_max(
      kSource0, kDestination, 4U, kPriorityLow, true);
  scheduler.submit_gemm(
      kSource0, kSource1, kDestination, 2U, 3U, 4U, kPriorityLow);
  expect(scheduler.tasks().size() == 5U,
         "not all workload APIs created tasks");

  bool invalid_length_rejected = false;
  try {
    scheduler.submit_vector_add(
        kSource0, kSource1, kDestination, 0U, kPriorityLow);
  } catch (const std::invalid_argument&) {
    invalid_length_rejected = true;
  }
  expect(invalid_length_rejected,
         "invalid vector length was not rejected");
}

}  // namespace

int main() {
  try {
    test_drivers();
    test_scheduler_interrupt_flow();
    test_scheduler_error_flow();
    test_submission_apis();
    std::cout << "PASS test=firmware\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL test=firmware reason=" << error.what() << '\n';
    return 1;
  }
}
