#ifndef SOC_REGISTERS_HPP
#define SOC_REGISTERS_HPP

#include <cstdint>

namespace soc {

inline constexpr std::uint32_t REG_SOC_ID = 0x000U;
inline constexpr std::uint32_t REG_VERSION = 0x004U;
inline constexpr std::uint32_t REG_CTRL = 0x008U;
inline constexpr std::uint32_t REG_STATUS = 0x00CU;
inline constexpr std::uint32_t REG_IRQ_STATUS = 0x010U;
inline constexpr std::uint32_t REG_IRQ_ENABLE = 0x014U;
inline constexpr std::uint32_t REG_TIMER_CTRL = 0x018U;
inline constexpr std::uint32_t REG_TIMER_VALUE = 0x01CU;
inline constexpr std::uint32_t REG_DMA_SRC_ADDR = 0x020U;
inline constexpr std::uint32_t REG_DMA_DST_ADDR = 0x024U;
inline constexpr std::uint32_t REG_DMA_LEN_BYTES = 0x028U;
inline constexpr std::uint32_t REG_DMA_CTRL = 0x02CU;
inline constexpr std::uint32_t REG_DMA_STATUS = 0x030U;
inline constexpr std::uint32_t REG_CMD_OPCODE = 0x034U;
inline constexpr std::uint32_t REG_CMD_SRC0_ADDR = 0x038U;
inline constexpr std::uint32_t REG_CMD_SRC1_ADDR = 0x03CU;
inline constexpr std::uint32_t REG_CMD_DST_ADDR = 0x040U;
inline constexpr std::uint32_t REG_CMD_LEN = 0x044U;
inline constexpr std::uint32_t REG_CMD_M = 0x048U;
inline constexpr std::uint32_t REG_CMD_N = 0x04CU;
inline constexpr std::uint32_t REG_CMD_K = 0x050U;
inline constexpr std::uint32_t REG_CMD_FLAGS = 0x054U;
inline constexpr std::uint32_t REG_CMD_PRIORITY = 0x058U;
inline constexpr std::uint32_t REG_CMD_SUBMIT = 0x05CU;
inline constexpr std::uint32_t REG_CMD_STATUS = 0x060U;
inline constexpr std::uint32_t REG_PERF_SELECT = 0x064U;
inline constexpr std::uint32_t REG_PERF_VALUE = 0x068U;
inline constexpr std::uint32_t REG_PERF_VALUE_HI = 0x06CU;
inline constexpr std::uint32_t REG_ERROR_STATUS = 0x070U;
inline constexpr std::uint32_t REG_CMD_ID = 0x074U;
inline constexpr std::uint32_t REG_SCHED_CTRL = 0x078U;
inline constexpr std::uint32_t REG_QUEUE_STATUS = 0x07CU;

inline constexpr std::uint32_t SOC_ID_VALUE = 0x534F4301U;
inline constexpr std::uint32_t VERSION_VALUE = 0x00010000U;

inline constexpr unsigned CTRL_ENABLE_BIT = 0U;
inline constexpr unsigned CTRL_PERF_CLEAR_BIT = 1U;
inline constexpr unsigned CTRL_PRIORITY_POLICY_BIT = 2U;
inline constexpr unsigned STATUS_READY_BIT = 0U;
inline constexpr unsigned STATUS_BUSY_BIT = 1U;
inline constexpr unsigned STATUS_ERROR_BIT = 2U;
inline constexpr unsigned TIMER_ENABLE_BIT = 0U;
inline constexpr unsigned TIMER_PERIODIC_BIT = 1U;
inline constexpr unsigned TIMER_INTERVAL_LSB = 8U;
inline constexpr unsigned DMA_CTRL_START_BIT = 0U;
inline constexpr unsigned DMA_CTRL_IRQ_ENABLE_BIT = 1U;
inline constexpr unsigned DMA_STATUS_BUSY_BIT = 0U;
inline constexpr unsigned DMA_STATUS_DONE_BIT = 1U;
inline constexpr unsigned DMA_STATUS_ERROR_BIT = 2U;
inline constexpr unsigned CMD_SUBMIT_BIT = 0U;
inline constexpr unsigned CMD_STATUS_DONE_BIT = 0U;
inline constexpr unsigned CMD_STATUS_ERROR_BIT = 1U;
inline constexpr unsigned CMD_STATUS_FULL_BIT = 2U;
inline constexpr unsigned CMD_STATUS_EMPTY_BIT = 3U;
inline constexpr unsigned CMD_STATUS_PENDING_BIT = 4U;
inline constexpr unsigned SCHED_POLICY_BIT = 0U;
inline constexpr unsigned SCHED_STARVATION_LSB = 8U;
inline constexpr unsigned SCHED_STARVATION_WIDTH = 8U;
inline constexpr unsigned QUEUE_OCCUPANCY_LSB = 0U;
inline constexpr unsigned QUEUE_HIGH_WATER_LSB = 8U;
inline constexpr unsigned QUEUE_FULL_BIT = 16U;
inline constexpr unsigned QUEUE_EMPTY_BIT = 17U;

inline constexpr unsigned IRQ_SOURCE_COUNT = 5U;
inline constexpr unsigned IRQ_DMA_DONE_BIT = 0U;
inline constexpr unsigned IRQ_CMD_DONE_BIT = 1U;
inline constexpr unsigned IRQ_ACCEL_DONE_BIT = 2U;
inline constexpr unsigned IRQ_ERROR_BIT = 3U;
inline constexpr unsigned IRQ_TIMER_BIT = 4U;

inline constexpr std::uint32_t AXIL_RESP_OKAY = 0U;
inline constexpr std::uint32_t AXIL_RESP_SLVERR = 2U;

inline constexpr std::uint32_t ERR_NONE = 0U;
inline constexpr std::uint32_t ERR_ILLEGAL_MMIO = 1U;
inline constexpr std::uint32_t ERR_READ_ONLY = 2U;
inline constexpr std::uint32_t ERR_DMA_BUSY = 3U;
inline constexpr std::uint32_t ERR_DMA_LENGTH = 4U;
inline constexpr std::uint32_t ERR_ADDRESS = 5U;
inline constexpr std::uint32_t ERR_QUEUE_FULL = 6U;
inline constexpr std::uint32_t ERR_OPCODE = 7U;
inline constexpr std::uint32_t ERR_DIMENSION = 8U;
inline constexpr std::uint32_t ERR_SPM_BOUNDS = 9U;
inline constexpr std::uint32_t ERR_INTERNAL = 15U;

inline constexpr std::uint32_t CMD_OP_INVALID = 0U;
inline constexpr std::uint32_t CMD_OP_DMA_COPY = 1U;
inline constexpr std::uint32_t CMD_OP_VECTOR_ADD = 2U;
inline constexpr std::uint32_t CMD_OP_VECTOR_MULTIPLY = 3U;
inline constexpr std::uint32_t CMD_OP_VECTOR_SCALE = 4U;
inline constexpr std::uint32_t CMD_OP_VECTOR_RELU = 5U;
inline constexpr std::uint32_t CMD_OP_VECTOR_CLAMP = 6U;
inline constexpr std::uint32_t CMD_OP_REDUCE_SUM = 7U;
inline constexpr std::uint32_t CMD_OP_REDUCE_MAX = 8U;
inline constexpr std::uint32_t CMD_OP_GEMM = 9U;

inline constexpr std::uint32_t SCHED_ROUND_ROBIN = 0U;
inline constexpr std::uint32_t SCHED_PRIORITY_FIRST = 1U;

inline constexpr std::uint32_t EXEC_TARGET_INVALID = 0U;
inline constexpr std::uint32_t EXEC_TARGET_DMA = 1U;
inline constexpr std::uint32_t EXEC_TARGET_VECTOR = 2U;
inline constexpr std::uint32_t EXEC_TARGET_REDUCTION = 3U;
inline constexpr std::uint32_t EXEC_TARGET_GEMM = 4U;

inline constexpr unsigned ELEMENT_WIDTH = 16U;
inline constexpr unsigned DEFAULT_MAX_VECTOR_LENGTH = 256U;
inline constexpr unsigned DEFAULT_MAX_REDUCTION_LENGTH = 256U;
inline constexpr unsigned FLAG_SIGNED_BIT = 0U;
inline constexpr unsigned FLAG_SATURATE_BIT = 1U;
inline constexpr unsigned FLAG_IRQ_ON_DONE_BIT = 2U;

inline constexpr std::uint32_t PERF_TOTAL_CYCLES = 0U;
inline constexpr std::uint32_t PERF_DMA_ACTIVE_CYCLES = 1U;
inline constexpr std::uint32_t PERF_DMA_STALLED_CYCLES = 2U;
inline constexpr std::uint32_t PERF_ACCEL_ACTIVE_CYCLES = 3U;
inline constexpr std::uint32_t PERF_ACCEL_STALLED_CYCLES = 4U;
inline constexpr std::uint32_t PERF_QUEUE_HIGH_WATER = 5U;
inline constexpr std::uint32_t PERF_COMMANDS_COMPLETED = 6U;
inline constexpr std::uint32_t PERF_BYTES_READ = 7U;
inline constexpr std::uint32_t PERF_BYTES_WRITTEN = 8U;
inline constexpr std::uint32_t PERF_IRQ_LATENCY = 9U;
inline constexpr std::uint32_t PERF_SCHEDULER_STALLS = 10U;
inline constexpr std::uint32_t PERF_COUNTER_INVALID = 15U;

}  // namespace soc

#endif
