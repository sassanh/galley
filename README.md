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
👉 **[sassanh.codeberg.page/galley](https://sassanh.codeberg.page/galley/)**

* **[Getting Started](https://sassanh.codeberg.page/galley/getting_started)** — Installation, requirements, and running your first parser.
* **[Included Languages](https://sassanh.codeberg.page/galley/languages)** — Reference implementations including JSON, Augmented JSON, and the self-hosting Grammar parser.
* **[Configuration & Flags](https://sassanh.codeberg.page/galley/configuration)** — Complete list of generator CLI and runtime compiler flags.
* **[Writing a Language](https://sassanh.codeberg.page/galley/writing_a_language)** — Creating new grammars, directory layout, and compiling custom targets.
* **[Reduction Procedures](https://sassanh.codeberg.page/galley/procedures)** — Writing Zig hooks to manipulate ASTs, handle state, and clean up nodes.
* **[Core Architecture](https://sassanh.codeberg.page/galley/architecture)** — Under the hood of Galley's stack-overflow recovery, lexer-less design, and self-hosting roadmap.
* **[AST Allocations](https://sassanh.codeberg.page/galley/ast_node_allocations)** — AST node pool optimizations and top-down vs. bottom-up allocation limits.
* **[Benchmarks](https://sassanh.codeberg.page/galley/benchmarks)** — Precision benchmarking guidelines and throughput metrics.

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
zig build -Doptimize=ReleaseFast ll-flat_json -- languages/json/sample-code.json
```

---

## Performance

Parsed bytes throughput on an **Apple M1 Pro** using the `flat_json` grammar:

| Mode | LL Throughput | LR Throughput |
| :--- | :--- | :--- |
| **No AST** | **~723 MB/s** | **~285 MB/s** |
| **AST, no terminals in AST** | **~444 MB/s** | **~108 MB/s** |
| **AST, terminals in AST** | **~310 MB/s** | **~93 MB/s** |

---

## License

MIT © 2026 Sassan Haradji
