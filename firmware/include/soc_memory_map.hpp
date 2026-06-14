#ifndef SOC_MEMORY_MAP_HPP
#define SOC_MEMORY_MAP_HPP

#include <cstddef>
#include <cstdint>

namespace soc {

inline constexpr std::uint32_t DATA_BYTES = 4U;
inline constexpr std::uint32_t SPM_BASE_ADDR = 0x10000000U;
inline constexpr std::size_t SPM_SIZE_BYTES = 65536U;
inline constexpr std::uint32_t DRAM_BASE_ADDR = 0x80000000U;
inline constexpr std::size_t DRAM_SIZE_BYTES = 1048576U;
inline constexpr unsigned DEFAULT_DMA_BURST_BEATS = 4U;

}  // namespace soc

#endif
