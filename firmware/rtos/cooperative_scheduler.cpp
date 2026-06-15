#include "cooperative_scheduler.hpp"

#include <algorithm>
#include <limits>
#include <stdexcept>
#include <utility>

#include "soc_memory_map.hpp"
#include "soc_registers.hpp"

namespace firmware {
namespace {

constexpr unsigned kBitsPerByte = 8U;
constexpr std::uint32_t kElementBytes =
    soc::ELEMENT_WIDTH / kBitsPerByte;

std::uint32_t checked_product(std::uint32_t lhs, std::uint32_t rhs) {
  const auto product =
      static_cast<std::uint64_t>(lhs) * static_cast<std::uint64_t>(rhs);
  if (product > std::numeric_limits<std::uint32_t>::max()) {
    throw std::overflow_error("workload byte count overflow");
  }
  return static_cast<std::uint32_t>(product);
}

}  // namespace

CooperativeScheduler::CooperativeScheduler(Mmio& mmio)
    : mmio_(mmio),
      dma_(mmio),
      accelerator_(mmio),
      interrupts_(mmio),
      timer_(mmio),
      performance_(mmio) {}

void CooperativeScheduler::boot(std::uint32_t timer_interval_cycles) {
  mmio_.write(soc::REG_CTRL, register_bit(soc::CTRL_ENABLE_BIT));
  const auto interrupt_mask =
      register_bit(soc::IRQ_DMA_DONE_BIT) |
      register_bit(soc::IRQ_CMD_DONE_BIT) |
      register_bit(soc::IRQ_ACCEL_DONE_BIT) |
      register_bit(soc::IRQ_ERROR_BIT) |
      register_bit(soc::IRQ_TIMER_BIT);
  interrupts_.enable(interrupt_mask);
  if (timer_interval_cycles == 0U) {
    timer_.stop();
  } else {
    timer_.start_periodic(timer_interval_cycles);
  }
}

void CooperativeScheduler::run_once() {
  ++scheduler_calls_;
  if (interrupts_.asserted()) {
    service_interrupts();
  }

  const auto selected = select_ready_task();
  if (!selected.has_value()) {
    if (!all_tasks_terminal()) {
      ++software_scheduler_stalls_;
    }
    return;
  }

  Task& task = tasks_[*selected];
  try {
    dispatch(task);
  } catch (const std::exception& error) {
    fail_task(task, error.what());
  }
}

bool CooperativeScheduler::all_tasks_terminal() const {
  return std::all_of(tasks_.begin(), tasks_.end(), [](const Task& task) {
    return task.state == TaskState::DONE || task.state == TaskState::ERROR;
  });
}

const std::vector<Task>& CooperativeScheduler::tasks() const {
  return tasks_;
}

const std::vector<TaskId>& CooperativeScheduler::dispatch_order() const {
  return dispatch_order_;
}

const std::vector<TaskId>& CooperativeScheduler::completion_order() const {
  return completion_order_;
}

std::uint64_t CooperativeScheduler::timer_ticks() const {
  return timer_ticks_;
}

std::uint64_t CooperativeScheduler::software_scheduler_stalls() const {
  return software_scheduler_stalls_;
}

PerformanceSnapshot CooperativeScheduler::performance_snapshot() {
  return PerformanceSnapshot{
      performance_.read(soc::PERF_TOTAL_CYCLES),
      performance_.read(soc::PERF_DMA_ACTIVE_CYCLES),
      performance_.read(soc::PERF_DMA_STALLED_CYCLES),
      performance_.read(soc::PERF_ACCEL_ACTIVE_CYCLES),
      performance_.read(soc::PERF_ACCEL_STALLED_CYCLES),
      performance_.read(soc::PERF_QUEUE_HIGH_WATER),
      performance_.read(soc::PERF_COMMANDS_COMPLETED),
      performance_.read(soc::PERF_BYTES_READ),
      performance_.read(soc::PERF_BYTES_WRITTEN),
      performance_.read(soc::PERF_IRQ_LATENCY),
      performance_.read(soc::PERF_SCHEDULER_STALLS)};
}

TaskId CooperativeScheduler::add_task(
    std::string name, std::uint32_t priority, WorkloadDescriptor workload,
    TaskPhase initial_phase) {
  if (tasks_.size() >= soc::FIRMWARE_TASK_SLOT_COUNT) {
    throw std::length_error("firmware task capacity exceeded");
  }
  const auto task_id = static_cast<TaskId>(tasks_.size());
  tasks_.push_back(Task{task_id, std::move(name), priority, TaskState::READY,
                        initial_phase, workload, scheduler_calls_, 0U, ""});
  return task_id;
}

std::optional<std::size_t> CooperativeScheduler::select_ready_task() const {
  std::optional<std::size_t> selected;
  for (std::size_t index = 0; index < tasks_.size(); ++index) {
    const Task& candidate = tasks_[index];
    if (candidate.state != TaskState::READY ||
        !resource_available(candidate)) {
      continue;
    }
    if (!selected.has_value() ||
        candidate.priority > tasks_[*selected].priority) {
      selected = index;
    }
  }
  return selected;
}

bool CooperativeScheduler::resource_available(const Task& task) const {
  if (task.phase == TaskPhase::EXECUTE) {
    return !active_accelerator_task_.has_value();
  }
  if (task.phase == TaskPhase::COMPLETE) {
    return true;
  }
  return !active_dma_task_.has_value();
}

void CooperativeScheduler::dispatch(Task& task) {
  task.state = TaskState::RUNNING;
  dispatch_order_.push_back(task.id);
  if (task.phase == TaskPhase::COMPLETE) {
    finish_task(task);
  } else if (task.phase == TaskPhase::EXECUTE) {
    dispatch_accelerator(task);
  } else {
    dispatch_dma(task);
  }
}

void CooperativeScheduler::dispatch_dma(Task& task) {
  std::uint32_t source = 0U;
  std::uint32_t destination = 0U;
  std::uint32_t length = 0U;
  switch (task.phase) {
    case TaskPhase::COPY:
      source = task.workload.source0;
      destination = task.workload.destination;
      length = task.workload.length;
      break;
    case TaskPhase::LOAD_SOURCE0:
      source = task.workload.source0;
      destination = scratch_source0(task);
      length = source0_bytes(task);
      break;
    case TaskPhase::LOAD_SOURCE1:
      source = task.workload.source1;
      destination = scratch_source1(task);
      length = source1_bytes(task);
      break;
    case TaskPhase::STORE_OUTPUT:
      source = scratch_destination(task);
      destination = task.workload.destination;
      length = output_bytes(task);
      break;
    case TaskPhase::EXECUTE:
    case TaskPhase::COMPLETE:
      throw std::logic_error("invalid DMA task phase");
  }

  dma_.start(source, destination, length);
  active_dma_task_ = static_cast<std::size_t>(task.id);
  task.state = TaskState::BLOCKED_ON_DMA;
}

void CooperativeScheduler::dispatch_accelerator(Task& task) {
  accelerator_.submit(make_command(task));
  active_accelerator_task_ = static_cast<std::size_t>(task.id);
  task.state = TaskState::BLOCKED_ON_ACCEL;
}

void CooperativeScheduler::service_interrupts() {
  const auto pending = interrupts_.pending();
  std::uint32_t acknowledged = 0U;

  const auto dma_mask = register_bit(soc::IRQ_DMA_DONE_BIT);
  if ((pending & dma_mask) != 0U) {
    if (active_dma_task_.has_value()) {
      complete_dma(tasks_[*active_dma_task_], dma_.status());
    }
    dma_.clear_status();
    acknowledged |= dma_mask;
  }

  const auto command_mask = register_bit(soc::IRQ_CMD_DONE_BIT);
  const auto accelerator_mask = register_bit(soc::IRQ_ACCEL_DONE_BIT);
  if ((pending & command_mask) != 0U) {
    if (active_accelerator_task_.has_value()) {
      complete_accelerator(tasks_[*active_accelerator_task_],
                           accelerator_.status());
    }
    accelerator_.clear_status();
    acknowledged |= command_mask;
  }
  if ((pending & accelerator_mask) != 0U) {
    acknowledged |= accelerator_mask;
  }

  const auto timer_mask = register_bit(soc::IRQ_TIMER_BIT);
  if ((pending & timer_mask) != 0U) {
    ++timer_ticks_;
    acknowledged |= timer_mask;
  }

  const auto error_mask = register_bit(soc::IRQ_ERROR_BIT);
  if ((pending & error_mask) != 0U) {
    const auto errors = mmio_.read(soc::REG_ERROR_STATUS);
    if (errors != 0U) {
      mmio_.write(soc::REG_ERROR_STATUS, errors);
    }
    acknowledged |= error_mask;
  }

  if (acknowledged != 0U) {
    interrupts_.acknowledge(acknowledged);
  }
}

void CooperativeScheduler::complete_dma(
    Task& task, const CompletionStatus& status) {
  active_dma_task_.reset();
  if (!status.done || status.error) {
    fail_task(task, "DMA completion reported an error");
    return;
  }

  switch (task.phase) {
    case TaskPhase::COPY:
      finish_task(task);
      break;
    case TaskPhase::LOAD_SOURCE0:
      task.phase =
          source1_bytes(task) == 0U ? TaskPhase::EXECUTE
                                   : TaskPhase::LOAD_SOURCE1;
      task.state = TaskState::READY;
      break;
    case TaskPhase::LOAD_SOURCE1:
      task.phase = TaskPhase::EXECUTE;
      task.state = TaskState::READY;
      break;
    case TaskPhase::STORE_OUTPUT:
      finish_task(task);
      break;
    case TaskPhase::EXECUTE:
    case TaskPhase::COMPLETE:
      fail_task(task, "DMA completed in an invalid task phase");
      break;
  }
}

void CooperativeScheduler::complete_accelerator(
    Task& task, const CompletionStatus& status) {
  active_accelerator_task_.reset();
  if (!status.done || status.error) {
    fail_task(task, "accelerator completion reported an error");
    return;
  }
  task.phase = TaskPhase::STORE_OUTPUT;
  task.state = TaskState::READY;
}

void CooperativeScheduler::fail_task(Task& task, const std::string& message) {
  task.state = TaskState::ERROR;
  task.error_message = message;
  task.completed_at = scheduler_calls_;
  if (active_dma_task_ == static_cast<std::size_t>(task.id)) {
    active_dma_task_.reset();
  }
  if (active_accelerator_task_ == static_cast<std::size_t>(task.id)) {
    active_accelerator_task_.reset();
  }
}

void CooperativeScheduler::finish_task(Task& task) {
  task.phase = TaskPhase::COMPLETE;
  task.state = TaskState::DONE;
  task.completed_at = scheduler_calls_;
  completion_order_.push_back(task.id);
}

std::uint32_t CooperativeScheduler::scratch_source0(const Task& task) const {
  return soc::SPM_BASE_ADDR + task.id * soc::FIRMWARE_TASK_SLOT_BYTES +
         soc::FIRMWARE_SOURCE0_OFFSET;
}

std::uint32_t CooperativeScheduler::scratch_source1(const Task& task) const {
  return soc::SPM_BASE_ADDR + task.id * soc::FIRMWARE_TASK_SLOT_BYTES +
         soc::FIRMWARE_SOURCE1_OFFSET;
}

std::uint32_t CooperativeScheduler::scratch_destination(
    const Task& task) const {
  return soc::SPM_BASE_ADDR + task.id * soc::FIRMWARE_TASK_SLOT_BYTES +
         soc::FIRMWARE_DESTINATION_OFFSET;
}

std::uint32_t CooperativeScheduler::source0_bytes(const Task& task) const {
  if (task.workload.kind == WorkloadKind::GEMM) {
    return checked_product(
        checked_product(task.workload.rows, task.workload.inner),
        kElementBytes);
  }
  return checked_product(task.workload.length, kElementBytes);
}

std::uint32_t CooperativeScheduler::source1_bytes(const Task& task) const {
  if (task.workload.kind == WorkloadKind::GEMM) {
    return checked_product(
        checked_product(task.workload.inner, task.workload.columns),
        kElementBytes);
  }
  if (task.workload.kind == WorkloadKind::VECTOR &&
      task.workload.opcode != soc::CMD_OP_VECTOR_RELU) {
    return checked_product(task.workload.length, kElementBytes);
  }
  return 0U;
}

std::uint32_t CooperativeScheduler::output_bytes(const Task& task) const {
  if (task.workload.kind == WorkloadKind::GEMM) {
    return checked_product(
        checked_product(task.workload.rows, task.workload.columns),
        kElementBytes);
  }
  if (task.workload.kind == WorkloadKind::REDUCTION) {
    return kElementBytes;
  }
  return checked_product(task.workload.length, kElementBytes);
}

CommandDescriptor CooperativeScheduler::make_command(const Task& task) const {
  return CommandDescriptor{
      task.workload.opcode,
      scratch_source0(task),
      source1_bytes(task) == 0U ? 0U : scratch_source1(task),
      scratch_destination(task),
      task.workload.length,
      task.workload.rows,
      task.workload.columns,
      task.workload.inner,
      task.workload.flags,
      task.priority,
      kCommandIdBase + task.id};
}

}  // namespace firmware
