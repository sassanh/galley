# Included Languages

## Table of Contents
- [Overview](#overview)
- [Bundled Grammars](#bundled-grammars)
  - [JSON (`languages/json`)](#json-languagesjson)
  - [Augmented JSON (`languages/augmented-json`)](#augmented-json-languagesaugmented-json)
  - [Flat JSON (`languages/flat_json`)](#flat-json-languagesflat_json)
  - [Lisp (`languages/lisp`)](#lisp-languageslisp)
  - [Lua (`languages/lua`)](#lua-languageslua)
  - [Grammar Parser (`languages/grammar`)](#grammar-parser-languagesgrammar)
- [Choosing Between LL and LR](#choosing-between-ll-and-lr)
- [Building and Running Included Languages](#building-and-running-included-languages)

---

## Overview

Galley ships with several ready-to-use grammar definitions located in the `languages/` directory. These bundled languages serve both as comprehensive benchmarks for parsing speed and as architectural reference implementations for defining your own grammars.

---

## Bundled Grammars

### JSON (`languages/json`)
The standard RFC 8259 JSON implementation. It supports full recursive object and array structures, floating-point numbers, unicode escape sequences, and string content literals.
- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.
- **Hooks:** Implements `@drop_children`, `@drop_self`, and `@replace_with_children` in `procedures.zig` to keep memory allocations minimal during AST generation.
- **Test Inputs:** Contains `samples/code-01.json` and `samples/code-02.json`.

### Augmented JSON (`languages/augmented-json`)
An extended JSON variant designed to test extreme recursion depths and stress-test the parser's stack overflow recovery mechanisms. It introduces special grouping syntax (`*(...)` and `(...)`) that allows deeply nested structures without exceeding memory limits.
- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.
- **Hooks:** Demonstrates advanced reduction hooking and stack management.

### Flat JSON (`languages/flat_json`)
A variant of the standard JSON grammar designed to parse full, recursive JSON but optimized for maximum parser execution speed. Its grammar structure is refactored to use the minimum possible number of variables (non-terminals) by inlining patterns directly. Because each grammar variable generates a dedicated parsing function, minimizing variables results in fewer functions and a flatter call stack, enabling LLVM to optimize the compiled binary far more aggressively (yielding throughputs of over ~720 MB/s).
- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.

### Lisp (`languages/lisp`)
A Lisp grammar covering lists, symbols, numbers, strings, reader macros, comments, vectors, arrays, and multiple top-level forms.
- **Parser Engines:** `ll.grm` is provided.
- **Test Inputs:** Contains `samples/code-01.lisp` and `samples/code-02.lisp`.

### Lua (`languages/lua`)
A compact Lua subset grammar that demonstrates keyword-led statements, function declarations, returns, function-call expressions, integer literals, strings, and keyed table constructors.
- **Parser Engines:** `ll.grm` is provided.
- **Test Inputs:** Contains `samples/code-01.lua`.

### Grammar Parser (`languages/grammar`)
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
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/json --parser-type LL
zig build -Doptimize=ReleaseFast ll-json -- languages/json/samples/code-01.json

# Generate and test the LR parser for the Grammar specification itself
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/grammar --parser-type LR
zig build -Doptimize=ReleaseFast lr-grammar -- languages/grammar/sample-code.grm
```
