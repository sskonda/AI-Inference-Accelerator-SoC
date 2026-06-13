# UVM Organization

The class-based environment is separated into packages, interfaces, reusable agents,
environment configuration, virtual sequences, scoreboards, coverage, assertion binds,
and tests.

The AXI-Lite agent implements the exact single-beat subset documented by this project.
The memory agent can inject latency and backpressure while maintaining a byte-addressable
mirror. Scoreboards consume monitor transactions rather than peeking at driver state.
