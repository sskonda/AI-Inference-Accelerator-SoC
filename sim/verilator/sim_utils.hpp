#pragma once

#include <filesystem>
#include <string>

#if VM_COVERAGE
#include "verilated_cov.h"
#endif

namespace sim {

constexpr const char* kCoverageOption = "--coverage";
constexpr const char* kCoverageFileOption = "--coverage-file";
constexpr const char* kDefaultCoverageFile = "coverage/coverage.dat";

inline bool is_coverage_argument(const std::string& argument) {
  return argument == kCoverageOption || argument == kCoverageFileOption;
}

inline std::string coverage_file_from_arguments(int argc, char** argv) {
  for (int index = 1; index + 1 < argc; ++index) {
    if (std::string(argv[index]) == kCoverageFileOption) {
      return argv[index + 1];
    }
  }
  return kDefaultCoverageFile;
}

inline bool coverage_requested(int argc, char** argv) {
  for (int index = 1; index < argc; ++index) {
    if (std::string(argv[index]) == kCoverageOption) {
      return true;
    }
  }
  return false;
}

inline void write_coverage_if_requested(int argc, char** argv) {
#if VM_COVERAGE
  if (coverage_requested(argc, argv)) {
    const std::filesystem::path coverage_path =
        coverage_file_from_arguments(argc, argv);
    if (coverage_path.has_parent_path()) {
      std::filesystem::create_directories(coverage_path.parent_path());
    }
    VerilatedCov::write(coverage_path.string().c_str());
  }
#else
  (void)argc;
  (void)argv;
#endif
}

}  // namespace sim
