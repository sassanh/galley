# Getting Started

## Table of Contents

- [What You Need](#what-you-need)
- [Your First Parser](#your-first-parser)
  - [Parse existing JSON](#parse-existing-json)
  - [Try the LR parser too](#try-the-lr-parser-too)
- [Next Steps](#next-steps)

---

## What You Need

- [Zig 0.16+](https://ziglang.org/download/) — this is the only runtime requirement
- [uv](https://docs.astral.sh/uv/) — to run the grammar generator
- A terminal or shell

---

## Your First Parser

The fastest path is to start with an example grammar that already ships with the repo. Run all commands from the repository root directory.

### Parse existing JSON

```sh
# 1. Generate the LL parse table
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/json --parser-type LL

# 2. Build and run it with release optimization for maximum throughput
zig build -Doptimize=ReleaseFast ll-json -- languages/json/samples/code-01.json
```

That's it — `languages/json/samples/code-01.json` parses at hundreds of megabytes per second.

### Try the LR parser too

```sh
# 1. Generate the LR parse table
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/json --parser-type LR

# 2. Build and run it
zig build -Doptimize=ReleaseFast lr-json -- languages/json/samples/code-01.json
```

---

## Next Steps

Now that you have verified the bundled JSON parsers work, you can explore the other [included languages](languages.md), check out the [CLI configuration and flags](configuration.md), or start [writing your own custom language](writing_a_language.md).
