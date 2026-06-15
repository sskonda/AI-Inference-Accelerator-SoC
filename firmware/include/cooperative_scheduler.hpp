#ifndef COOPERATIVE_SCHEDULER_HPP
#define COOPERATIVE_SCHEDULER_HPP

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "hardware_drivers.hpp"
#include "task.hpp"

namespace firmware {

struct PerformanceSnapshot {
  std::uint64_t total_cycles = 0U;
  std::uint64_t dma_active_cycles = 0U;
  std::uint64_t dma_stalled_cycles = 0U;
  std::uint64_t accelerator_active_cycles = 0U;
  std::uint64_t accelerator_stalled_cycles = 0U;
  std::uint64_t queue_high_water = 0U;
  std::uint64_t commands_completed = 0U;
  std::uint64_t bytes_read = 0U;
  std::uint64_t bytes_written = 0U;
  std::uint64_t interrupt_latency = 0U;
  std::uint64_t scheduler_stalls = 0U;
};

class CooperativeScheduler {
 public:
  explicit CooperativeScheduler(Mmio& mmio);

  void boot(std::uint32_t timer_interval_cycles = 0U);

  TaskId submit_dma_copy(std::uint32_t source, std::uint32_t destination,
                         std::uint32_t length_bytes, std::uint32_t priority);
  TaskId submit_vector_add(std::uint32_t source0, std::uint32_t source1,
                           std::uint32_t destination, std::uint32_t length,
                           std::uint32_t priority, bool signed_mode = false,
                           bool saturate = false);
  TaskId submit_vector_relu_or_clamp(
      std::uint32_t source0, std::uint32_t source1,
      std::uint32_t destination, std::uint32_t length, bool clamp,
      std::uint32_t priority, bool signed_mode = true);
  TaskId submit_reduce_sum(std::uint32_t source, std::uint32_t destination,
                           std::uint32_t length, std::uint32_t priority,
                           bool signed_mode = false,
                           bool saturate = false);
  TaskId submit_reduce_max(std::uint32_t source, std::uint32_t destination,
                           std::uint32_t length, std::uint32_t priority,
                           bool signed_mode = false);
  TaskId submit_gemm(std::uint32_t source0, std::uint32_t source1,
                     std::uint32_t destination, std::uint32_t rows,
                     std::uint32_t columns, std::uint32_t inner,
                     std::uint32_t priority, bool signed_mode = false,
                     bool saturate = false);

  void run_once();
  bool all_tasks_terminal() const;
  const std::vector<Task>& tasks() const;
  const std::vector<TaskId>& dispatch_order() const;
  const std::vector<TaskId>& completion_order() const;
  std::uint64_t timer_ticks() const;
  std::uint64_t software_scheduler_stalls() const;
  PerformanceSnapshot performance_snapshot();

 private:
  static constexpr std::uint32_t kCommandIdBase = 0x1000U;

  TaskId add_task(std::string name, std::uint32_t priority,
                  WorkloadDescriptor workload, TaskPhase initial_phase);
  std::optional<std::size_t> select_ready_task() const;
  bool resource_available(const Task& task) const;
  void dispatch(Task& task);
  void dispatch_dma(Task& task);
  void dispatch_accelerator(Task& task);
  void service_interrupts();
  void complete_dma(Task& task, const CompletionStatus& status);
  void complete_accelerator(Task& task, const CompletionStatus& status);
  void fail_task(Task& task, const std::string& message);
  void finish_task(Task& task);
  std::uint32_t scratch_source0(const Task& task) const;
  std::uint32_t scratch_source1(const Task& task) const;
  std::uint32_t scratch_destination(const Task& task) const;
  std::uint32_t source0_bytes(const Task& task) const;
  std::uint32_t source1_bytes(const Task& task) const;
  std::uint32_t output_bytes(const Task& task) const;
  CommandDescriptor make_command(const Task& task) const;

  Mmio& mmio_;
  DmaDriver dma_;
  AcceleratorDriver accelerator_;
  InterruptDriver interrupts_;
  TimerDriver timer_;
  PerformanceDriver performance_;
  std::vector<Task> tasks_;
  std::vector<TaskId> dispatch_order_;
  std::vector<TaskId> completion_order_;
  std::optional<std::size_t> active_dma_task_;
  std::optional<std::size_t> active_accelerator_task_;
  std::uint64_t scheduler_calls_ = 0U;
  std::uint64_t timer_ticks_ = 0U;
  std::uint64_t software_scheduler_stalls_ = 0U;
};

}  // namespace firmware

#endif
