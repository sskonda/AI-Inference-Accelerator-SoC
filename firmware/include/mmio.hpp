#ifndef MMIO_HPP
#define MMIO_HPP

#include <cstdint>

namespace firmware {

class Mmio {
 public:
  virtual ~Mmio() = default;

  virtual std::uint32_t read(std::uint32_t offset) = 0;
  virtual void write(std::uint32_t offset, std::uint32_t value) = 0;
  virtual bool irq_asserted() const = 0;
};

}  // namespace firmware

#endif
