#!/usr/bin/env bash
set -euo pipefail

printf "\ngrammar (ll)\n--------------------\n"
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/grammar --parser-type LL
printf "\ngrammar/ll.grm\n"
zig build -Doptimize=ReleaseFast grammar -- languages/grammar/ll.grm --verbosity 0 --iterations 200000
printf "\ngrammar/lr.grm\n"
zig build -Doptimize=ReleaseFast grammar -- languages/grammar/lr.grm --verbosity 0 --iterations 200000
printf "\njson/ll.grm\n"
zig build -Doptimize=ReleaseFast grammar -- languages/json/ll.grm --verbosity 0 --iterations 200000
printf "\nsanbus-logic/lr.grm\n"
zig build -Doptimize=ReleaseFast grammar -- languages/sanbus-logic/lr.grm --verbosity 0 --iterations 100000
printf "\ntest-ll/ll.grm\n"
zig build -Doptimize=ReleaseFast grammar -- languages/test-ll/ll.grm --verbosity 0 --iterations 100000
printf "\ntest-ll1/ll.grm\n"
zig build -Doptimize=ReleaseFast grammar -- languages/test-ll1/ll.grm --verbosity 0 --iterations 100000

printf "\ngrammar (lr)\n--------------------\n"
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/grammar --parser-type LR
printf "\ngrammar/ll.grm\n"
zig build -Doptimize=ReleaseFast grammar -- languages/grammar/ll.grm --verbosity 0 --iterations 2000
printf "\ngrammar/lr.grm\n"
zig build -Doptimize=ReleaseFast grammar -- languages/grammar/lr.grm --verbosity 0 --iterations 2000
printf "\njson/ll.grm\n"
zig build -Doptimize=ReleaseFast grammar -- languages/json/ll.grm --verbosity 0 --iterations 2000
printf "\nsanbus-logic/lr.grm\n"
zig build -Doptimize=ReleaseFast grammar -- languages/sanbus-logic/lr.grm --verbosity 0 --iterations 1000
printf "\ntest-ll/ll.grm\n"
zig build -Doptimize=ReleaseFast grammar -- languages/test-ll/ll.grm --verbosity 0 --iterations 1000
printf "\ntest-ll1/ll.grm\n"
zig build -Doptimize=ReleaseFast grammar -- languages/test-ll1/ll.grm --verbosity 0 --iterations 1000

printf "\njson\n--------------------\n"
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/json --parser-type LL
printf "\nlarge-sample-code.json\n"
zig build -Doptimize=ReleaseFast json -- languages/json/large-sample-code.json --verbosity 0 --iterations 3

printf "\nsanbus\n--------------------\n"
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/sanbus-logic --parser-type LR
printf "\ntodo.lgc\n"
zig build -Doptimize=ReleaseFast sanbus-logic -- ../tests/reducer/todo.lgc --verbosity 0 --iterations 2000

printf "\ntest-ll\n--------------------\n"
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/test-ll --parser-type LL
printf "\nsample-code\n"
zig build -Doptimize=ReleaseFast test-ll -- languages/test-ll/sample-code --verbosity 0 --iterations 200000
printf "\nlarge-sample-code\n"
zig build -Doptimize=ReleaseFast test-ll -- languages/test-ll/large-sample-code --verbosity 0 --iterations 2000

printf "\ntest-ll1\n--------------------\n"
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/test-ll1 --parser-type LL
printf "\nsample-code\n"
zig build -Doptimize=ReleaseFast test-ll1 -- languages/test-ll1/sample-code --verbosity 0 --iterations 2000
