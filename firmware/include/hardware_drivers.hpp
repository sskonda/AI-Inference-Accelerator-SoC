#ifndef HARDWARE_DRIVERS_HPP
#define HARDWARE_DRIVERS_HPP

#include <cstdint>

#include "mmio.hpp"

namespace firmware {

constexpr std::uint32_t register_bit(unsigned index) {
  return std::uint32_t{1} << index;
}

struct CommandDescriptor {
  std::uint32_t opcode = 0U;
  std::uint32_t source0 = 0U;
  std::uint32_t source1 = 0U;
  std::uint32_t destination = 0U;
  std::uint32_t length = 0U;
  std::uint32_t rows = 0U;
  std::uint32_t columns = 0U;
  std::uint32_t inner = 0U;
  std::uint32_t flags = 0U;
  std::uint32_t priority = 0U;
  std::uint32_t command_id = 0U;
};

struct CompletionStatus {
  bool busy = false;
  bool done = false;
  bool error = false;
};

class DmaDriver {
 public:
  explicit DmaDriver(Mmio& mmio) : mmio_(mmio) {}

  void start(std::uint32_t source, std::uint32_t destination,
             std::uint32_t length_bytes);
  CompletionStatus status();
  void clear_status();

 private:
  Mmio& mmio_;
};

class AcceleratorDriver {
 public:
  explicit AcceleratorDriver(Mmio& mmio) : mmio_(mmio) {}

  void submit(const CommandDescriptor& command);
  CompletionStatus status();
  void clear_status();

 private:
  Mmio& mmio_;
};

class InterruptDriver {
 public:
  explicit InterruptDriver(Mmio& mmio) : mmio_(mmio) {}

  void enable(std::uint32_t mask);
  std::uint32_t pending();
  void acknowledge(std::uint32_t mask);
  bool asserted() const;

 private:
  Mmio& mmio_;
};

class TimerDriver {
 public:
  explicit TimerDriver(Mmio& mmio) : mmio_(mmio) {}

  void start_periodic(std::uint32_t interval_cycles);
  void stop();
  std::uint32_t value();

 private:
  Mmio& mmio_;
};

class PerformanceDriver {
 public:
  explicit PerformanceDriver(Mmio& mmio) : mmio_(mmio) {}

  std::uint64_t read(std::uint32_t counter_id);
  void clear();

 private:
  Mmio& mmio_;
};

}  // namespace firmware

#endif
