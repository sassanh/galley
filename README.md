<picture>
  <source media="(prefers-color-scheme: dark)" srcset="resources/banner-dark.webp">
  <source media="(prefers-color-scheme: light)" srcset="resources/banner-light.webp">
  <img alt="Galley — Directly encoded speed. Zero boilerplate." src="resources/banner-light.webp">
</picture>

# Galley

> **Alpha** — interfaces and grammar format may change between releases.

A parser generator and high-performance parser runtime written in [Zig](https://ziglang.org). Galley takes a grammar definition (`.grm` file), generates a native Zig parser from it, and produces parsers that run at **hundreds of megabytes per second** with zero heap allocation during parsing.

## How It Works

Galley has two halves:

1. **The generator** (`initial-parser-generator/`) — a Python tool that reads a `.grm` grammar file and emits a `_parse-table.zig` file. It supports LL, LR, and GLR grammars.
2. **The runtime** (`src/`) — a Zig library that links the generated parse table, runs the parser, and optionally builds an AST.

Because the parse table is compiled directly into Zig code, there is no interpretation at runtime. The generated parser *is* the table: grammar rules become functions, the call stack becomes the parse stack. This is what enables the throughput numbers below.

### No Separate Lexer

Galley works directly on raw input bytes. There is no separate lexer or tokenisation phase — reading identifiers, strings, numbers, and whitespace all happens inside the parser itself. This eliminates the token-stream indirection common in traditional parser generators and keeps the hot path as tight as possible.

### Stack Overflow Recovery

Using the call stack as the parse stack raises an obvious concern for deeply nested inputs. Galley addresses this with a signal-based recovery mechanism (`stack-overflow.zig`) that catches stack overflow conditions in most cases and surfaces them as recoverable errors rather than hard crashes. The `languages/augmented-json/` grammar exists specifically to exercise and verify this behaviour.

### Hooks

Symbols in a grammar rule can be annotated with `@hook-name` to call a user-defined Zig procedure at that point during the parse. Hooks can be attached to any variable, alternative, or individual symbol within a right-hand side, allowing semantic actions — such as AST reshaping — to be expressed inline without a separate tree-walking pass.

### AST Manipulation Utilities

Parsing raw characters directly means the AST can accumulate structural noise: an identifier parsed letter-by-letter will produce one node per character, and LL grammars often introduce tail variables whose nodes serve no semantic purpose. Galley provides utilities to clean this up *at parse time*, without a post-processing step:

- **Drop nodes** — discard a subtree entirely (e.g. remove per-character nodes after an identifier has been consumed)
- **Merge / replace** — collapse a tail variable into its parent, or hoist children up to replace their parent node
- **Underscore prefix** — variables whose name starts with `_` (e.g. `_IdTail`, `_StringContent`) never generate AST nodes at all, so the noise never exists in the first place. This is the zero-cost option: no node is created, so nothing needs to be dropped later.

Because all other operations work on the pre-allocated node pool via `u16` index surgery, they carry no allocation cost.

### The AST

When AST mode is enabled, Galley builds a **doubly-linked, parent-aware tree** using a flat pre-allocated pool of `u16`-indexed nodes. Each node carries:

- `first_child` / `last_child` — for top-down traversal
- `next` / `prior` — for sibling traversal
- `parent` — for walking upward

The `u16` indices keep the working set small enough to stay in L1/L2 cache. The pre-allocated pool means zero allocations during a parse — every reset is a `memset` on the previously used portion.

## Benchmarks

All benchmarks run with `zig build -Doptimize=ReleaseFast` on an **Apple M1 Pro**, parsing a JSON input file.

| Mode | Throughput |
| --- | --- |
| No AST | **~402 MB/s** |
| AST, no procedures, no terminals in AST | **~268 MB/s** |
| AST, no procedures, terminals in AST | **~214 MB/s** |
| AST, procedures, no terminals in AST | **~159 MB/s** |
| AST, procedures, terminals in AST | **~131 MB/s** |

The old table-driven prototype topped out at **1.88 MB/s** for LR and **984 KB/s** for LL. The current implementation is roughly **200–400× faster**.

## Grammar Format

Grammars are defined in `.grm` files. Rules use a simple line-based syntax: the rule name on its own line, followed by alternatives prefixed with `|`. Terminals are quoted strings or named generative terminals (lowercase identifiers). Variables are CamelCase.

```
Start
 |Rules

Rules
 |Rule RulesTail

Rule
 |VariableSymbol block_start RightHandSides block_end

RightHandSideLine
 |"|" RightHandSide
 |"#" AnyContent   # comment
```

### Augmented JSON

The `languages/augmented-json/` grammar extends standard JSON with a recursive grouping construct (`*(...)` and `(...)`) that produces arbitrarily deep nesting. Its purpose is to verify that Galley handles deeply nested inputs without stack overflowing — a meaningful guarantee when the call stack *is* the parse stack. The standard `languages/json/` grammar is plain JSON with no extensions.

## Project Structure

```
initial-parser-generator/   Python parser generator (LL, LR, GLR)
  main.py                   CLI entry point
  ll/                       LL parse table + Zig code emitter
  lr/                       LR parse table + Zig code emitter
  glr/                      GLR parse table + Zig code emitter

src/                        Zig runtime
  main.zig                  Entry point, benchmarking harness
  utilities/
    data-structures/
      astnode.zig           ASTNode and ASTAllocator (u16-indexed pool)
      context.zig           Reader, token buffer, seek state
      data-structures.zig   Shared types (Rule, Symbol, StaticIntMap…)
    string.zig              Human-readable size/number formatting
    stack-overflow.zig      Stack overflow recovery via signal handling

languages/                  Example grammars
  grammar/                  The grammar language itself (ll.grm + lr.grm)
  json/                     JSON parser
  augmented-json/           Recursive-nesting stress test (deep-stack safety)
  test-ll/                  LL(*) test grammar
  test-ll1/                 LL(1) test grammar
```

## Building

Requires [Zig 0.16+](https://ziglang.org/download/) and [Python 3.12+](https://www.python.org/) with [uv](https://github.com/astral-sh/uv).

**Generate a parse table:**

```sh
cd initial-parser-generator
uv run main.py --language ../languages/json --parser-type LL
```

This writes `languages/json/_parse-table.zig`.

**Build and run a parser:**

```sh
zig build -Doptimize=ReleaseFast json -- languages/json/sample-code.json --iterations 10000 --verbosity 0
```

**Run tests:**

```sh
zig build test
```

## Generator CLI Options

| Flag | Description |
| --- | --- |
| `--language <path>` | Path to the language directory containing a `.grm` file |
| `--parser-type LL\|LR\|GLR` | Parser algorithm to use |
| `--no-ast` | Generate parser without AST support |
| `--no-procedures` | Omit user-defined procedure dispatch |
| `--ast-for-terminals` | Include terminal tokens as AST leaf nodes |
| `--no-ast-for-terminals` | Omit terminals from the AST (default, faster) |
| `--input-size <N>` | Set the input size cap (determines `u16`/`u32` index type) |
| `--graph` | Emit an HTML grammar graph |
| `--graphviz` | Emit a Graphviz HTML graph |
| `--generate-logs` | Write per-step logs to `./logs/` |

## Parser Runtime CLI Options

| Flag | Description |
| --- | --- |
| `<FILE>` | Input file to parse |
| `--iterations <N>` | Repeat the parse N times (for benchmarking) |
| `--warmup-iterations <N>` | Warmup iterations before timing starts |
| `--verbosity <0-2>` | Logging verbosity |
| `--disable-stack-overflow-recovery` | Skip the signal-based stack guard |

## Roadmap

The Python generator is a bootstrap tool. A long-term goal is to make Galley self-hosting: feed the `.grm` grammar format into Galley itself and use hooks to perform the semantic actions the Python generator currently handles, producing a parser that generates its own parse tables. The Python generator will remain for as long as this is not yet done.

## License

MIT © 2026 Sassan Haradji
