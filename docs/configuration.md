# Configuration & Flags

## Table of Contents
- [Overview](#overview)
- [Generator CLI Options](#generator-cli-options)
- [Runtime Executable Flags](#runtime-executable-flags)
- [Quick Reference](#quick-reference)

---

## Overview

Galley's pipeline consists of two distinct stages: generating the Zig parser tables via Python (`initial-parser-generator/main.py`), and running the compiled Zig binary. Both stages expose fine-grained command-line flags to tune AST generation, logging, graphing, and benchmarking behavior.

---

## Generator CLI Options

When running the grammar generator via `uv run`, pass options after the script path:

```sh
uv run --project initial-parser-generator initial-parser-generator/main.py [OPTIONS]
```

| Flag | Argument | Description | Default |
| :--- | :--- | :--- | :--- |
| `--language` | `<PATH>` | **Required.** Path to the target language directory (e.g. `languages/json`). | None |
| `--parser-type` | `LL` \| `LR` | Selects whether to generate a top-down LL or bottom-up LR parser. | First found (`LL`) |
| `--with-ast` / `--no-ast` | Flag | Enables or disables AST construction. Disabling AST construction maximizes raw syntax validation speed. | `--with-ast` |
| `--with-procedures` / `--no-procedures` | Flag | Enables or disables executing reduction hooks defined in `procedures.zig`. | `--with-procedures` |
| `--ast-for-terminals` / `--no-ast-for-terminals` | Flag | Controls whether individual terminal characters allocate AST nodes. Disabling terminal nodes keeps AST allocations minimal. | `--no-ast-for-terminals` |
| `--input-size` | `<BITS>` | Number of bit-width integer bits required to represent input file length pointers (e.g. `16` or `32`). | `16` |
| `--generate-logs` / `--logs-directory` | `<PATH>` | Generates step-by-step internal debugging logs of the parser table generation process. | `./logs` |
| `--graph` | Flag | Generates a static HTML visualization graph of the grammar state machine. | Disabled |
| `--graphviz` | Flag | Generates a Graphviz `.dot` / HTML graph representation of grammar transitions. | Disabled |

---

## Runtime Executable Flags

When invoking a built binary directly or via `zig build`, pass arguments after `--`:

```sh
zig build -Doptimize=ReleaseFast ll-json -- [OPTIONS] <FILE>
```

| Flag | Short | Argument | Description | Default |
| :--- | :--- | :--- | :--- | :--- |
| `--verbosity` | `-v` | `<0-2>` | Verbosity level. `0` prints benchmark speed; `1` prints parsed AST structure and metrics; `2` outputs detailed execution traces. | `0` |
| `--iterations` | `-r` | `<INT>` | Number of times to repeat parsing the file. Highly useful for getting stable throughput averages during benchmarking. | `1` |
| `--warmup-iterations` | `-w` | `<INT>` | Number of warmup parse passes before recording benchmark timers to ensure CPU cache saturation. | `0` |
| `--disable-stack-overflow-recovery` | None | Flag | Disables dynamic stack overflow recovery, falling back to static stack boundaries. | Enabled |
| `<FILE>` | None | `<PATH>` | **Required.** Path to the source code file to parse. | None |

> [!IMPORTANT]
> When compiling the parser with `-Doptimize=ReleaseFast` (the default optimization mode for benchmarking), all debugging instrumentation, execution logging, verbosity traces, and even source location tracking (line/column numbers) are completely disabled and compiled out to maximize parsing throughput. For debugging, syntax error reporting, or verbose parsing traces, compile the parser without `-Doptimize=ReleaseFast` (which defaults to Debug mode).

---

## Quick Reference

### Standard Production Generation & Run
```sh
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/json --parser-type LL
zig build -Doptimize=ReleaseFast ll-json -- languages/json/samples/code-01.json
```

### High-Precision Benchmarking Loop (100 Iterations with 10 Warmups)
```sh
zig build -Doptimize=ReleaseFast ll-json -- -r 100 -w 10 languages/json/samples/code-02.json
```

### AST Debugging & Inspection
```sh
zig build ll-json -- -v 1 languages/json/samples/code-01.json
```
