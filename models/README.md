# Reference Models

C++ models are linked into the fast simulation harness. Python models support independent
test-vector checks and performance-result processing.

Models use explicit fixed-width arithmetic and reproduce only documented architectural
overflow, truncation, clamp, and saturation behavior.

`cpp/vector_model.hpp` is the executable reference for packed vector operations. It is
independent of RTL state and memory sequencing and is used for both directed and seeded
randomized comparisons.
