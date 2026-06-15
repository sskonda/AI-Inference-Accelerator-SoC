#ifndef TASK_HPP
#define TASK_HPP

#include <cstdint>
#include <string>

namespace firmware {

using TaskId = std::uint32_t;

enum class TaskState {
  READY,
  RUNNING,
  BLOCKED_ON_DMA,
  BLOCKED_ON_ACCEL,
  DONE,
  ERROR
};

enum class WorkloadKind {
  DMA_COPY,
  VECTOR,
  REDUCTION,
  GEMM
};

enum class TaskPhase {
  COPY,
  LOAD_SOURCE0,
  LOAD_SOURCE1,
  EXECUTE,
  STORE_OUTPUT,
  COMPLETE
};

struct WorkloadDescriptor {
  WorkloadKind kind = WorkloadKind::DMA_COPY;
  std::uint32_t opcode = 0U;
  std::uint32_t source0 = 0U;
  std::uint32_t source1 = 0U;
  std::uint32_t destination = 0U;
  std::uint32_t length = 0U;
  std::uint32_t rows = 0U;
  std::uint32_t columns = 0U;
  std::uint32_t inner = 0U;
  std::uint32_t flags = 0U;
};

struct Task {
  TaskId id = 0U;
  std::string name;
  std::uint32_t priority = 0U;
  TaskState state = TaskState::READY;
  TaskPhase phase = TaskPhase::COPY;
  WorkloadDescriptor workload;
  std::uint64_t submitted_at = 0U;
  std::uint64_t completed_at = 0U;
  std::string error_message;
};

}  // namespace firmware

#endif
