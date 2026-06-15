# Reference Models

C++ models are linked into the fast simulation harness. Python models support independent
test-vector checks and performance-result processing.

Models use explicit fixed-width arithmetic and reproduce only documented architectural
overflow, truncation, clamp, and saturation behavior.

`cpp/vector_model.hpp` is the executable reference for packed vector operations. It is
independent of RTL state and memory sequencing and is used for both directed and seeded
randomized comparisons.

`cpp/reduction_model.hpp` preserves a wide software accumulator for sum and applies the
same documented final conversion as hardware. Maximum is compared in the selected
signedness.
