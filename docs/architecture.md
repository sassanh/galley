# Core Architecture

## Table of Contents

- [Overview](#overview)
- [Unified No-Lexer Design](#unified-no-lexer-design)
- [Native Call-Stack Execution](#native-call-stack-execution)
- [Dynamic Stack-Overflow Recovery](#dynamic-stack-overflow-recovery)
- [Dense Integer Node Pooling](#dense-integer-node-pooling)
- [Role of the Python Generator](#role-of-the-python-generator)
- [Self-Hosting Roadmap](#self-hosting-roadmap)

---

## Overview

Galley achieves parsing speeds tens to hundreds of times faster than traditional table-driven parser generators by fundamentally rethinking how parsers interact with memory and the CPU. Rather than interpreting state transitions at runtime, Galley directly encodes grammar semantics into compile-time Zig execution paths.

---

## Unified No-Lexer Design

Traditional parsers split execution into two passes: a lexer (tokenizer) that scans source text and allocates token objects on the heap, followed by a parser that consumes those tokens.

Galley eliminates the separate lexer pass entirely. Character matching and structural grammar reduction happen simultaneously in a single, unified pass over the source byte buffer. By avoiding token allocation and intermediate buffering, memory bus traffic is reduced by over 50%.

---

## Native Call-Stack Execution

In both generated LL recursive-descent and LR recursive-ascent parsers, Galley leverages the native CPU execution call stack as the grammar parsing stack.

Instead of dynamically allocating stack frame objects or pushing/popping state IDs in an array loop, grammar transitions compile directly into native machine function calls (`call` and `ret` instructions). This allows modern CPUs to fully utilize their hardware return address stacks (RAS) and branch prediction units, resulting in near-zero overhead state transitions.

---

## Dynamic Stack-Overflow Recovery

Leveraging the native CPU call stack introduces a potential risk when parsing deeply recursive structures (such as thousands of nested JSON arrays): exceeding the operating system thread stack limit.

To prevent crashes, Galley includes a runtime stack-overflow recovery mechanism. As parsing approaches the stack limit, the runtime intercepts execution and dynamically transitions to heap-backed continuation frames. This guarantees safety on arbitrarily deep input files while maintaining maximum bare-metal speed during normal execution depths.

---

## Dense Integer Node Pooling

When AST construction is enabled, Galley avoids allocating individual nodes via the system heap (`malloc`). Instead, nodes are allocated from contiguous, preallocated memory pools (`ASTAllocator`).

Furthermore, AST nodes reference their parents, children, and siblings using compact integer indices (`u16` or bit-width defined by `--input-size`) rather than 64-bit pointers. This cuts AST memory consumption in half, ensures dense cache packing in CPU L1/L2 caches, and allows resetting the entire parser state between iterations in \(O(1)\) time simply by zeroing a counter.

---

## Role of the Python Generator

Currently, the grammar analysis engine resides in Python (`initial-parser-generator/`). The Python generator is responsible for:

1. Parsing the `.grm` definition files.
2. Computing FIRST, FOLLOW, and nullable sets.
3. Constructing deterministic LL(k) lookup tables or LR/LALR shift-reduce automatas.
4. Emitting highly optimized, zero-boilerplate Zig code (`_ll-parser.zig` and `_lr-parser.zig`).

Because this step happens entirely ahead-of-time (AOT), the runtime Zig binary carries zero generator overhead or Python dependencies.

---

## Self-Hosting Roadmap

Galley already ships with a formal specification of its own grammar syntax (`languages/galley`). The generated parser can successfully parse and validate `.grm` files at hundreds of megabytes per second.

The ultimate roadmap goal is to port the parser table generation algorithms from Python to Zig. Once completed, Galley will become a fully self-hosted, standalone compiler capable of compiling and generating new parsers entirely within a single native binary.
