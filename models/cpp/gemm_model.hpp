#ifndef GEMM_MODEL_HPP
#define GEMM_MODEL_HPP

#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <vector>

#include "vector_model.hpp"

namespace model {

inline std::vector<std::uint16_t> gemm_operation(
    const std::vector<std::uint16_t>& matrix_a,
    const std::vector<std::uint16_t>& matrix_b, std::size_t rows,
    std::size_t columns, std::size_t inner, bool signed_mode,
    bool saturate) {
  if (rows == 0U || columns == 0U || inner == 0U ||
      matrix_a.size() != rows * inner ||
      matrix_b.size() != inner * columns) {
    throw std::invalid_argument("invalid matrix dimensions");
  }

  std::vector<std::uint16_t> result(rows * columns, 0U);
  for (std::size_t row = 0; row < rows; ++row) {
    for (std::size_t column = 0; column < columns; ++column) {
      if (signed_mode) {
        std::int64_t accumulator = 0;
        for (std::size_t inner_index = 0; inner_index < inner;
             ++inner_index) {
          const auto lhs =
              signed_element(matrix_a[row * inner + inner_index]);
          const auto rhs =
              signed_element(matrix_b[inner_index * columns + column]);
          accumulator += static_cast<std::int64_t>(lhs) * rhs;
        }
        result[row * columns + column] =
            signed_result(accumulator, saturate);
      } else {
        std::uint64_t accumulator = 0U;
        for (std::size_t inner_index = 0; inner_index < inner;
             ++inner_index) {
          accumulator +=
              static_cast<std::uint64_t>(
                  matrix_a[row * inner + inner_index]) *
              matrix_b[inner_index * columns + column];
        }
        result[row * columns + column] =
            unsigned_result(accumulator, saturate);
      }
    }
  }
  return result;
}

}  // namespace model

#endif
