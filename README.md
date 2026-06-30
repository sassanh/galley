<picture>
  <source media="(prefers-color-scheme: dark)" srcset="resources/banner-dark.webp">
  <source media="(prefers-color-scheme: light)" srcset="resources/banner-light.webp">
  <img alt="Galley — Directly encoded speed. Zero boilerplate." src="resources/banner-light.webp">
</picture>

# Galley

> **Alpha** — interfaces and grammar format may change between releases.

A parser generator and high-performance parser runtime written in [Zig](https://ziglang.org). Galley reads a grammar definition (`.grm` file), generates a native Zig parser, and produces recursive-descent and recursive-ascent parsers that run at **hundreds of megabytes per second** with zero heap allocation during parsing.

---

## Documentation

Full user guides and architectural documentation are available online at:
👉 **[sassanh.github.io/galley](https://sassanh.github.io/galley/)**

* **[Getting Started](https://sassanh.github.io/galley/getting_started)** — Installation, requirements, and running your first parser.
* **[Included Languages](https://sassanh.github.io/galley/languages)** — Reference implementations including JSON, Augmented JSON, Lisp, Lua, and the self-hosting Grammar parser.
* **[Configuration & Flags](https://sassanh.github.io/galley/configuration)** — Complete list of generator CLI and runtime compiler flags.
* **[Writing a Language](https://sassanh.github.io/galley/writing_a_language)** — Creating new grammars, directory layout, and compiling custom targets.
* **[Reduction Procedures](https://sassanh.github.io/galley/procedures)** — Writing Zig hooks to manipulate ASTs, handle state, and clean up nodes.
* **[Core Architecture](https://sassanh.github.io/galley/architecture)** — Under the hood of Galley's stack-overflow recovery, lexer-less design, and self-hosting roadmap.
* **[AST Allocations](https://sassanh.github.io/galley/ast_node_allocations)** — AST node pool optimizations and top-down vs. bottom-up allocation limits.
* **[Benchmarks](https://sassanh.github.io/galley/benchmarks)** — Precision benchmarking guidelines and throughput metrics.

For a local, up-to-date comparison against third-party parsers see [BENCHMARKS.md](BENCHMARKS.md).

---

## Quick Start

### Prerequisites

* [Zig 0.16+](https://ziglang.org/download/) — Native compiler toolchain
* [uv](https://docs.astral.sh/uv/) — Python package and script runner

### Compile & Run a Bundled Parser

```sh
# 1. Generate the Zig parse table for JSON
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/json --parser-type LL

# 2. Build and run the parser in ReleaseFast mode
zig build -Doptimize=ReleaseFast ll-flat_json -- languages/json/samples/code-01.json
```

---

## Benchmarked Grammar Coverage

Galley benchmarks are meant to show both throughput and grammar breadth.

| Grammar | What it exercises | Parsers |
| :--- | :--- | :--- |
| **JSON** | Recursive data, strings, numbers, arrays, objects, third-party comparison baseline | LL + LR |
| **Lisp** | Nested S-expressions, symbols, strings, integers, multiple top-level forms | LL |
| **Lua** | Keyword-led statements, functions, calls, returns, keyed table constructors | LL |
| **Galley Grammar** | The `.grm` language used to define Galley grammars | LL + LR |

For current Apple M1 Pro throughput numbers across all bundled grammars and the JSON
third-party comparison, see [BENCHMARKS.md](BENCHMARKS.md).

---

## License

MIT © 2026 Sassan Haradji
