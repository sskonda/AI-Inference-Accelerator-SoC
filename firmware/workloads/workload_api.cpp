#include "cooperative_scheduler.hpp"

#include <stdexcept>

#include "soc_registers.hpp"

namespace firmware {
namespace {

std::uint32_t operation_flags(bool signed_mode, bool saturate) {
  std::uint32_t flags = register_bit(soc::FLAG_IRQ_ON_DONE_BIT);
  if (signed_mode) {
    flags |= register_bit(soc::FLAG_SIGNED_BIT);
  }
  if (saturate) {
    flags |= register_bit(soc::FLAG_SATURATE_BIT);
  }
  return flags;
}

}  // namespace

TaskId CooperativeScheduler::submit_dma_copy(
    std::uint32_t source, std::uint32_t destination,
    std::uint32_t length_bytes, std::uint32_t priority) {
  if (length_bytes == 0U) {
    throw std::invalid_argument("DMA task length must be nonzero");
  }
  return add_task(
      "dma_copy", priority,
      WorkloadDescriptor{WorkloadKind::DMA_COPY, soc::CMD_OP_DMA_COPY,
                         source, 0U, destination, length_bytes},
      TaskPhase::COPY);
}

TaskId CooperativeScheduler::submit_vector_add(
    std::uint32_t source0, std::uint32_t source1,
    std::uint32_t destination, std::uint32_t length,
    std::uint32_t priority, bool signed_mode, bool saturate) {
  if (length == 0U || length > soc::DEFAULT_MAX_VECTOR_LENGTH) {
    throw std::invalid_argument("vector length is outside the supported range");
  }
  return add_task(
      "vector_add", priority,
      WorkloadDescriptor{WorkloadKind::VECTOR, soc::CMD_OP_VECTOR_ADD,
                         source0, source1, destination, length, 0U, 0U, 0U,
                         operation_flags(signed_mode, saturate)},
      TaskPhase::LOAD_SOURCE0);
}

TaskId CooperativeScheduler::submit_vector_relu_or_clamp(
    std::uint32_t source0, std::uint32_t source1,
    std::uint32_t destination, std::uint32_t length, bool clamp,
    std::uint32_t priority, bool signed_mode) {
  if (length == 0U || length > soc::DEFAULT_MAX_VECTOR_LENGTH) {
    throw std::invalid_argument("vector length is outside the supported range");
  }
  return add_task(
      clamp ? "vector_clamp" : "vector_relu", priority,
      WorkloadDescriptor{
          WorkloadKind::VECTOR,
          clamp ? soc::CMD_OP_VECTOR_CLAMP : soc::CMD_OP_VECTOR_RELU,
          source0,
          source1,
          destination,
          length,
          0U,
          0U,
          0U,
          operation_flags(signed_mode, false)},
      TaskPhase::LOAD_SOURCE0);
}

TaskId CooperativeScheduler::submit_reduce_sum(
    std::uint32_t source, std::uint32_t destination,
    std::uint32_t length, std::uint32_t priority, bool signed_mode,
    bool saturate) {
  if (length == 0U || length > soc::DEFAULT_MAX_REDUCTION_LENGTH) {
    throw std::invalid_argument(
        "reduction length is outside the supported range");
  }
  return add_task(
      "reduce_sum", priority,
      WorkloadDescriptor{WorkloadKind::REDUCTION, soc::CMD_OP_REDUCE_SUM,
                         source, 0U, destination, length, 0U, 0U, 0U,
                         operation_flags(signed_mode, saturate)},
      TaskPhase::LOAD_SOURCE0);
}

TaskId CooperativeScheduler::submit_reduce_max(
    std::uint32_t source, std::uint32_t destination,
    std::uint32_t length, std::uint32_t priority, bool signed_mode) {
  if (length == 0U || length > soc::DEFAULT_MAX_REDUCTION_LENGTH) {
    throw std::invalid_argument(
        "reduction length is outside the supported range");
  }
  return add_task(
      "reduce_max", priority,
      WorkloadDescriptor{WorkloadKind::REDUCTION, soc::CMD_OP_REDUCE_MAX,
                         source, 0U, destination, length, 0U, 0U, 0U,
                         operation_flags(signed_mode, false)},
      TaskPhase::LOAD_SOURCE0);
}

TaskId CooperativeScheduler::submit_gemm(
    std::uint32_t source0, std::uint32_t source1,
    std::uint32_t destination, std::uint32_t rows,
    std::uint32_t columns, std::uint32_t inner,
    std::uint32_t priority, bool signed_mode, bool saturate) {
  if (rows == 0U || rows > soc::DEFAULT_MAX_GEMM_M || columns == 0U ||
      columns > soc::DEFAULT_MAX_GEMM_N || inner == 0U ||
      inner > soc::DEFAULT_MAX_GEMM_K) {
    throw std::invalid_argument(
        "GEMM dimensions are outside the supported range");
  }
  return add_task(
      "gemm", priority,
      WorkloadDescriptor{WorkloadKind::GEMM, soc::CMD_OP_GEMM, source0,
                         source1, destination, 0U, rows, columns, inner,
                         operation_flags(signed_mode, saturate)},
      TaskPhase::LOAD_SOURCE0);
}

}  // namespace firmware
