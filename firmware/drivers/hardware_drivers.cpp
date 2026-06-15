#include "hardware_drivers.hpp"

#include <limits>
#include <stdexcept>

#include "soc_registers.hpp"

namespace firmware {

void DmaDriver::start(std::uint32_t source, std::uint32_t destination,
                      std::uint32_t length_bytes) {
  if (length_bytes == 0U) {
    throw std::invalid_argument("DMA length must be nonzero");
  }
  if (status().busy) {
    throw std::runtime_error("DMA engine is busy");
  }

  clear_status();
  mmio_.write(soc::REG_DMA_SRC_ADDR, source);
  mmio_.write(soc::REG_DMA_DST_ADDR, destination);
  mmio_.write(soc::REG_DMA_LEN_BYTES, length_bytes);
  mmio_.write(soc::REG_DMA_CTRL,
              register_bit(soc::DMA_CTRL_START_BIT) |
                  register_bit(soc::DMA_CTRL_IRQ_ENABLE_BIT));
}

CompletionStatus DmaDriver::status() {
  const auto value = mmio_.read(soc::REG_DMA_STATUS);
  return CompletionStatus{
      (value & register_bit(soc::DMA_STATUS_BUSY_BIT)) != 0U,
      (value & register_bit(soc::DMA_STATUS_DONE_BIT)) != 0U,
      (value & register_bit(soc::DMA_STATUS_ERROR_BIT)) != 0U};
}

void DmaDriver::clear_status() {
  mmio_.write(soc::REG_DMA_STATUS,
              register_bit(soc::DMA_STATUS_DONE_BIT) |
                  register_bit(soc::DMA_STATUS_ERROR_BIT));
}

void AcceleratorDriver::submit(const CommandDescriptor& command) {
  if (command.opcode == soc::CMD_OP_INVALID) {
    throw std::invalid_argument("invalid accelerator opcode");
  }
  const auto current_status = status();
  if (current_status.busy) {
    throw std::runtime_error("command processor is busy");
  }

  clear_status();
  mmio_.write(soc::REG_CMD_OPCODE, command.opcode);
  mmio_.write(soc::REG_CMD_SRC0_ADDR, command.source0);
  mmio_.write(soc::REG_CMD_SRC1_ADDR, command.source1);
  mmio_.write(soc::REG_CMD_DST_ADDR, command.destination);
  mmio_.write(soc::REG_CMD_LEN, command.length);
  mmio_.write(soc::REG_CMD_M, command.rows);
  mmio_.write(soc::REG_CMD_N, command.columns);
  mmio_.write(soc::REG_CMD_K, command.inner);
  mmio_.write(soc::REG_CMD_FLAGS, command.flags);
  mmio_.write(soc::REG_CMD_PRIORITY, command.priority);
  mmio_.write(soc::REG_CMD_ID, command.command_id);
  mmio_.write(soc::REG_CMD_SUBMIT, register_bit(soc::CMD_SUBMIT_BIT));
}

CompletionStatus AcceleratorDriver::status() {
  const auto value = mmio_.read(soc::REG_CMD_STATUS);
  return CompletionStatus{
      (value & register_bit(soc::CMD_STATUS_PENDING_BIT)) != 0U,
      (value & register_bit(soc::CMD_STATUS_DONE_BIT)) != 0U,
      (value & register_bit(soc::CMD_STATUS_ERROR_BIT)) != 0U};
}

void AcceleratorDriver::clear_status() {
  mmio_.write(soc::REG_CMD_STATUS,
              register_bit(soc::CMD_STATUS_DONE_BIT) |
                  register_bit(soc::CMD_STATUS_ERROR_BIT));
}

void InterruptDriver::enable(std::uint32_t mask) {
  mmio_.write(soc::REG_IRQ_ENABLE, mask);
}

std::uint32_t InterruptDriver::pending() {
  return mmio_.read(soc::REG_IRQ_STATUS);
}

void InterruptDriver::acknowledge(std::uint32_t mask) {
  mmio_.write(soc::REG_IRQ_STATUS, mask);
}

bool InterruptDriver::asserted() const { return mmio_.irq_asserted(); }

void TimerDriver::start_periodic(std::uint32_t interval_cycles) {
  constexpr auto kMaximumInterval =
      std::numeric_limits<std::uint32_t>::max() >>
      soc::TIMER_INTERVAL_LSB;
  if (interval_cycles == 0U || interval_cycles > kMaximumInterval) {
    throw std::invalid_argument("timer interval is outside the supported range");
  }
  mmio_.write(
      soc::REG_TIMER_CTRL,
      register_bit(soc::TIMER_ENABLE_BIT) |
          register_bit(soc::TIMER_PERIODIC_BIT) |
          (interval_cycles << soc::TIMER_INTERVAL_LSB));
}

void TimerDriver::stop() { mmio_.write(soc::REG_TIMER_CTRL, 0U); }

std::uint32_t TimerDriver::value() {
  return mmio_.read(soc::REG_TIMER_VALUE);
}

std::uint64_t PerformanceDriver::read(std::uint32_t counter_id) {
  mmio_.write(soc::REG_PERF_SELECT, counter_id);
  const auto low = mmio_.read(soc::REG_PERF_VALUE);
  const auto high = mmio_.read(soc::REG_PERF_VALUE_HI);
  return (static_cast<std::uint64_t>(high)
          << std::numeric_limits<std::uint32_t>::digits) |
         low;
}

void PerformanceDriver::clear() {
  mmio_.write(soc::REG_CTRL,
              register_bit(soc::CTRL_ENABLE_BIT) |
                  register_bit(soc::CTRL_PERF_CLEAR_BIT));
}

}  // namespace firmware
