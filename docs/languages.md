# Included Languages

## Table of Contents
- [Overview](#overview)
- [Bundled Grammars](#bundled-grammars)
  - [JSON (`languages/json`)](#json-languagesjson)
  - [JSON Structured AST (`languages/json-structured-ast`)](#json-structured-ast-languagesjson-structured-ast)
  - [Augmented JSON (`languages/augmented-json`)](#augmented-json-languagesaugmented-json)
  - [Lisp (`languages/lisp`)](#lisp-languageslisp)
  - [Lua (`languages/lua`)](#lua-languageslua)
  - [Grammar Parser (`languages/galley`)](#grammar-parser-languagesgalley)
- [Choosing Between LL and LR](#choosing-between-ll-and-lr)
- [Building and Running Included Languages](#building-and-running-included-languages)

---

## Overview

Galley ships with several ready-to-use grammar definitions located in the `languages/` directory. These bundled languages serve both as comprehensive benchmarks for parsing speed and as architectural reference implementations for defining your own grammars.

---

## Bundled Grammars

### JSON (`languages/json`)
The standard RFC 8259 JSON implementation used for JSON benchmarking. It supports full recursive object and array structures, floating-point numbers, unicode escape sequences, and string content literals. Its grammar is written with fewer non-terminals so the generated parser has fewer calls and less intermediate AST structure.
- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.

### JSON Structured AST (`languages/json-structured-ast`)
A full RFC 8259 JSON grammar with additional non-terminals for a richer AST shape. It parses the same language as `languages/json`, but preserves more intermediate structure and therefore has lower benchmark throughput.
- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.
- **Hooks:** Implements `@drop_children`, `@drop_self`, and `@replace_with_children` in `procedures.zig` to shape AST generation.

### Augmented JSON (`languages/augmented-json`)
An extended JSON variant designed to test extreme recursion depths and stress-test the parser's stack overflow recovery mechanisms. It introduces special grouping syntax (`*(...)` and `(...)`) that allows deeply nested structures without exceeding memory limits.
- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.
- **Hooks:** Demonstrates advanced reduction hooking and stack management.

### Lisp (`languages/lisp`)
A Lisp grammar covering lists, symbols, numbers, strings, reader macros, comments, vectors, arrays, and multiple top-level forms.
- **Parser Engines:** `ll.grm` is provided.

### Lua (`languages/lua`)
A Lua grammar that demonstrates keyword-led statements, function declarations, returns, function-call expressions, integer literals, strings, comments, and keyed table constructors.
- **Parser Engines:** `ll.grm` is provided.

### Grammar Parser (`languages/galley`)
The self-hosting definition of Galley's own `.grm` syntax! This language defines the exact structure of rule definitions, alternatives (`|`), variable symbols, quoted literals, and `@` annotations used across the compiler.
- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.

---

## Choosing Between LL and LR

When working with or creating languages in Galley, you can choose between two parsing paradigms:

1. **LL(k) Top-Down Parsing (`ll.grm`)**:
   - Generates recursive-descent parsing tables.
   - Ideal for clear, human-readable grammars where rules naturally decompose from top to bottom.
   - Requires eliminating left-recursion (e.g. rewrite `Expr | Expr "+" Number` to right-recursive or iterative form).

2. **LR / LALR Bottom-Up Parsing (`lr.grm`)**:
   - Generates deterministic shift-reduce state machines.
   - Easily handles left-recursive rules and complex expressions without restructuring.
   - Often produces highly optimized state transitions for dense programming languages.

---

## Building and Running Included Languages

To compile and benchmark any included language, generate its parse table using `uv` and invoke `zig build` from the repository root:

```sh
# Generate and test the LL parser for standard JSON
scripts/generate-parser --language languages/json --parser-type LL
zig build -Doptimize=ReleaseFast ll-json -- languages/json/samples/code-01.json

# Generate and test the LR parser for the Grammar specification itself
scripts/generate-parser --language languages/galley --parser-type LR
zig build -Doptimize=ReleaseFast lr-galley -- languages/galley/lr.grm
```
