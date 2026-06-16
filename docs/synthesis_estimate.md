# Synthesis Estimate

## Scope

This estimate is a generic structural view of the `soc_top` RTL. It is useful for
tracking relative changes in memory footprint, cell mix, and elaborated hierarchy size.
It is not a timing result, technology-mapped area result, or physical implementation
result.

The reproducible command is:

```sh
make synth-estimate
```

The flow reads the synthesizable SystemVerilog source list through the Yosys slang
frontend, ignores assertions and initial validation blocks, elaborates `soc_top`, runs
generic process conversion and optimization, and emits JSON and Markdown reports under
`reports/synth/`.

## Latest Result

| Metric | Value |
| --- | ---: |
| Tool | Yosys 0.66+94 |
| Wires | 3,238 |
| Wire bits | 44,718 |
| Public wires | 702 |
| Public wire bits | 10,750 |
| Ports | 42 |
| Port bits | 314 |
| Memories | 10 |
| Memory bits | 528,024 |
| Generic cells | 3,026 |

## Generic Cell Counts

| Cell | Count |
| --- | ---: |
| `$add` | 109 |
| `$and` | 27 |
| `$bmux` | 15 |
| `$demux` | 9 |
| `$dffe` | 6 |
| `$eq` | 156 |
| `$ge` | 44 |
| `$gt` | 70 |
| `$le` | 12 |
| `$logic_and` | 301 |
| `$logic_not` | 121 |
| `$logic_or` | 108 |
| `$lt` | 71 |
| `$meminit` | 3 |
| `$memrd_v2` | 52 |
| `$memwr_v2` | 131 |
| `$mod` | 5 |
| `$mul` | 47 |
| `$mux` | 1,168 |
| `$ne` | 107 |
| `$not` | 17 |
| `$or` | 29 |
| `$pmux` | 77 |
| `$reduce_and` | 76 |
| `$reduce_bool` | 49 |
| `$reduce_or` | 25 |
| `$sdff` | 32 |
| `$sdffe` | 124 |
| `$shiftx` | 1 |
| `$sub` | 34 |

## Interpretation

The large memory-bit count is expected. It is dominated by the simulation-scale
scratchpad and external-memory storage inferred by the integrated hierarchy. Generic
cell counts are best used to compare local revisions with the same tool version and
command line.
