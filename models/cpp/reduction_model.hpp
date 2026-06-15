#ifndef REDUCTION_MODEL_HPP
#define REDUCTION_MODEL_HPP

#include <algorithm>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <vector>

#include "soc_registers.hpp"
#include "vector_model.hpp"

namespace model {

inline std::uint16_t reduction_operation(
    std::uint32_t opcode, const std::vector<std::uint16_t>& source,
    bool signed_mode, bool saturate) {
  if (source.empty()) {
    throw std::invalid_argument("reduction source must not be empty");
  }

  if (opcode == soc::CMD_OP_REDUCE_SUM) {
    if (signed_mode) {
      std::int64_t sum = 0;
      for (const auto value : source) {
        sum += signed_element(value);
      }
      return signed_result(sum, saturate);
    }
    std::uint64_t sum = 0U;
    for (const auto value : source) {
      sum += value;
    }
    return unsigned_result(sum, saturate);
  }

  if (opcode == soc::CMD_OP_REDUCE_MAX) {
    if (signed_mode) {
      auto maximum = std::numeric_limits<std::int32_t>::min();
      for (const auto value : source) {
        maximum = std::max(maximum, signed_element(value));
      }
      return signed_result(maximum, false);
    }
    return *std::max_element(source.begin(), source.end());
  }

  throw std::invalid_argument("unsupported reduction opcode");
}

}  // namespace model

#endif
