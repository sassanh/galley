# Old Implementation

## LR

### **1.88 MBps**

    input size: 994

    ❯ ./zig-out/bin/sanbus-logic ../tests/reducer/todo.lgc --verbosity=0 --iterations=10000
    
     ╭───────────────────────────────────────╮
     │ 󱎫 5.27s (5266ms) 󰥔2026-05-15 10:32:57 │
     ╰───────────────────────────────────────╯

## LL

### **984.07 KBps**

     input size: 989

    ❯ ./zig-out/bin/test-ll languages/test-ll/sample-code --iterations=10000

     ╭─────────────────────────────────────────╮
     │ 󱎫 10.05s (10055ms) 󰥔2026-05-15 10:37:35 │
     ╰─────────────────────────────────────────╯

# New Implementation

## LL(1)

### **138.91 MBps**

     input size: 989

    ❯ ./zig-out/bin/test-ll1 languages/test-ll1/sample-code --iterations=1000000

     ╭───────────────────────────────────────╮
     │ 󱎫 7.12s (7122ms) 󰥔2026-05-15 10:43:21 │
     ╰───────────────────────────────────────╯

### **169.74 MBps**

    input size: 100661

    ❯ ./zig-out/bin/test-ll1 languages/test-ll1/sample-code --iterations=10000

     ╭───────────────────────────────────────╮
     │ 󱎫 5.93s (5927ms) 󰥔2026-05-15 10:39:40 │
     ╰───────────────────────────────────────╯

## LL(*)

### 90.40 MBps

    input size: 989

    ❯ ./zig-out/bin/test-ll languages/test-ll/sample-code --iterations=1000000

     ╭─────────────────────────────────────────╮
     │ 󱎫 10.94s (10936ms) 󰥔2026-05-16 08:29:17 │
     ╰─────────────────────────────────────────╯

### 99.41 MBps

    input size: 100799

    ❯ ./zig-out/bin/test-ll languages/test-ll/sample-code --iterations=10000

     ╭─────────────────────────────────────────╮
     │ 󱎫 10.14s (10137ms) 󰥔2026-05-16 08:35:28 │
     ╰─────────────────────────────────────────╯

## LL(*) without `try...` and `return error...`

### 106.22 MBps

    input size: 100799
    ❯ ./zig-out/bin/test-ll languages/test-ll/sample-code --iterations=10000

     ╭───────────────────────────────────────╮
     │ 󱎫 9.49s (9492ms) 󰥔2026-05-16 09:47:16 │
     ╰───────────────────────────────────────╯

### 128.70 MBps

    input size: 100000
    ❯ ./zig-out/bin/test-ll1 languages/test-ll1/sample-code --iterations=10000

     ╭───────────────────────────────────────╮
     │ 󱎫 7.77s (7769ms) 󰥔2026-05-16 10:00:51 │
     ╰───────────────────────────────────────╯

## LL(*) with u64, u32, u16, u8 switch matching

### 116.69 MBps

    input size: 100000
    ❯ ./zig-out/bin/test-ll languages/test-ll/sample-code --verbosity=1 --iterations=10000

     ╭───────────────────────────────────────╮
     │ 󱎫 8.57s (8567ms) 󰥔2026-05-17 01:24:03 │
     ╰───────────────────────────────────────╯

## LL(*) with u8, u16, u24 (arbitrary byte length) switch matching

### 119.33 MBps

    input size: 100000
    ❯ ./zig-out/bin/test-ll languages/test-ll/sample-code --verbosity=1 --iterations=10000

     ╭───────────────────────────────────────╮
     │ 󱎫 8.34s (8337ms) 󰥔2026-05-17 12:41:04 │
     ╰───────────────────────────────────────╯

### 150.33 MBps

    ❯ ./zig-out/bin/json languages/json/large-sample-code.json --iterations 30
    Parsed bytes:  1.47 GB
    Duration:      10,027,835,708 ns
    Throughput:    150.33 MB/s

## LL(*), added left-recursion-to-loop enhancement

### 153.08 MBps

    ❯ zig build -Doptimize=ReleaseFast json -- languages/json/large-sample-code.json --iterations 10 --verbosity 0
    Parsed bytes:  501.57 MB
    Duration:      3,276,455,333 ns
    Throughput:    153.08 MB/s

## data-structures.zig optimizations, removing column/line counters in ReleaseFast

### 173.02 MBps

    ❯ zig build -Doptimize=ReleaseFast json -- languages/json/large-sample-code.json --verbosity 0 --iterations 5
    Parsed bytes:  250.79 MB
    Duration:      1,449,490,500 ns
    Throughput:    173.02 MB/s

## using u16 instead of usize for code allocation along other improvements

### 371.82MBps

    ❯ zig build -Doptimize=ReleaseFast json -- languages/json/sample-code.json --iterations 20000
    Parsed bytes:  84.99 MB
    Duration:      228,580,875 ns
    Throughput:    371.82 MB/s

## increase the size of sample-code.json as well as micro improvements here and there

### 394.94MBps

    ❯ zig build -Doptimize=ReleaseFast json -- languages/json/sample-code.json --iterations 30000
    Parsed bytes:  509.61 MB
    Duration:      1,290,340,500 ns
    Throughput:    394.94 MB/s

## bigger sample.json

### 402.06MBps (no-ast)

    ❯ zig build -Doptimize=ReleaseFast json -- languages/json/sample-code.json --iterations 30000
    Parsed bytes:  509.61 MB
    Duration:      1,267,493,125 ns
    Throughput:    402.06 MB/s

### 268.48MBps (ast, no-procedures, no-ast-for-terminals)

    ❯ zig build -Doptimize=ReleaseFast json -- languages/json/sample-code.json --iterations 10000
    Parsed bytes:  175.54 MB
    Duration:      653,840,792 ns
    Throughput:    268.48 MB/s
    Nodes allocated:    7,039

### 214.37MBps (ast, no-procedures, ast-for-terminals)

    ❯ zig build -Doptimize=ReleaseFast json -- languages/json/sample-code.json --iterations 10000
    Parsed bytes:  175.54 MB
    Duration:      818,886,875 ns
    Throughput:    214.37 MB/s
    Nodes allocated:    12,407

### 158.96MBps (ast, procedures, no-ast-for-terminals)

    ❯ zig build -Doptimize=ReleaseFast json -- languages/json/sample-code.json --iterations 10000
    Parsed bytes:  175.54 MB
    Duration:      1,104,310,667 ns
    Throughput:    158.96 MB/s
    Nodes allocated:    7,039

### 130.68MBps (ast, procedures, ast-for-terminals)

    ❯ zig build -Doptimize=ReleaseFast json -- languages/json/sample-code.json --iterations 10000
    Parsed bytes:  175.54 MB
    Duration:      1,343,284,625 ns
    Throughput:    130.68 MB/s
    Nodes allocated:    12,407
