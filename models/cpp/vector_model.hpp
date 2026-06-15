#ifndef VECTOR_MODEL_HPP
#define VECTOR_MODEL_HPP

#include <algorithm>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <vector>

#include "soc_registers.hpp"

namespace model {

inline std::int32_t signed_element(std::uint16_t value) {
  constexpr std::uint32_t kSignBit = std::uint32_t{1}
                                     << (soc::ELEMENT_WIDTH - 1U);
  constexpr std::uint32_t kModulus = std::uint32_t{1}
                                     << soc::ELEMENT_WIDTH;
  const auto extended = static_cast<std::uint32_t>(value);
  return extended < kSignBit ? static_cast<std::int32_t>(extended)
                            : static_cast<std::int32_t>(extended - kModulus);
}

inline std::uint16_t signed_result(std::int64_t value, bool saturate) {
  constexpr auto kMinimum = std::numeric_limits<std::int16_t>::min();
  constexpr auto kMaximum = std::numeric_limits<std::int16_t>::max();
  if (saturate) {
    value = std::clamp(value, static_cast<std::int64_t>(kMinimum),
                       static_cast<std::int64_t>(kMaximum));
  }
  return static_cast<std::uint16_t>(
      static_cast<std::uint64_t>(value) & std::numeric_limits<std::uint16_t>::max());
}

inline std::uint16_t unsigned_result(std::uint64_t value, bool saturate) {
  constexpr auto kMaximum = std::numeric_limits<std::uint16_t>::max();
  if (saturate && value > kMaximum) {
    value = kMaximum;
  }
  return static_cast<std::uint16_t>(value & kMaximum);
}

inline std::uint16_t vector_element(std::uint32_t opcode, std::uint16_t lhs,
                                    std::uint16_t rhs, bool signed_mode,
                                    bool saturate) {
  if (signed_mode) {
    const auto signed_lhs = static_cast<std::int64_t>(signed_element(lhs));
    const auto signed_rhs = static_cast<std::int64_t>(signed_element(rhs));
    switch (opcode) {
      case soc::CMD_OP_VECTOR_ADD:
        return signed_result(signed_lhs + signed_rhs, saturate);
      case soc::CMD_OP_VECTOR_MULTIPLY:
      case soc::CMD_OP_VECTOR_SCALE:
        return signed_result(signed_lhs * signed_rhs, saturate);
      case soc::CMD_OP_VECTOR_RELU:
        return signed_result(std::max<std::int64_t>(signed_lhs, 0), false);
      case soc::CMD_OP_VECTOR_CLAMP:
        if (signed_lhs < 0 || signed_rhs < 0) {
          return 0U;
        }
        return signed_result(std::min(signed_lhs, signed_rhs), false);
      default:
        throw std::invalid_argument("unsupported vector opcode");
    }
  }

  const auto unsigned_lhs = static_cast<std::uint64_t>(lhs);
  const auto unsigned_rhs = static_cast<std::uint64_t>(rhs);
  switch (opcode) {
    case soc::CMD_OP_VECTOR_ADD:
      return unsigned_result(unsigned_lhs + unsigned_rhs, saturate);
    case soc::CMD_OP_VECTOR_MULTIPLY:
    case soc::CMD_OP_VECTOR_SCALE:
      return unsigned_result(unsigned_lhs * unsigned_rhs, saturate);
    case soc::CMD_OP_VECTOR_RELU:
      return lhs;
    case soc::CMD_OP_VECTOR_CLAMP:
      return std::min(lhs, rhs);
    default:
      throw std::invalid_argument("unsupported vector opcode");
  }
}

inline std::vector<std::uint16_t> vector_operation(
    std::uint32_t opcode, const std::vector<std::uint16_t>& source0,
    const std::vector<std::uint16_t>& source1, std::uint16_t scalar,
    bool signed_mode, bool saturate) {
  std::vector<std::uint16_t> result(source0.size());
  for (std::size_t index = 0; index < source0.size(); ++index) {
    const std::uint16_t rhs =
        opcode == soc::CMD_OP_VECTOR_SCALE
            ? scalar
            : (opcode == soc::CMD_OP_VECTOR_RELU ? 0U : source1.at(index));
    result[index] =
        vector_element(opcode, source0[index], rhs, signed_mode, saturate);
  }
  return result;
}

}  // namespace model

#endif
