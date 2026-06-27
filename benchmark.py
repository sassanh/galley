#!/usr/bin/env python3
import argparse
import os
import shlex
import subprocess
import sys

# Global environment generator command
GENERATOR_COMMAND = os.environ.get(
    "GENERATOR_COMMAND",
    "uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/",
)


def parse_zig_output(stdout_str):
    """
    Parses key-value metric lines from the zig build output.
    """
    metrics = {}
    for line in stdout_str.splitlines():
        line = line.strip()
        if ":" in line:
            key, val = line.split(":", 1)
            metrics[key.strip()] = val.strip()
    return metrics


def format_card(name, metrics, width=34, no_color=False, error_msg=None):
    """
    Formats a single benchmark result block into a list of strings representing card lines.
    """
    if no_color:
        RESET = ""
        BOLD = ""
        DIM = ""
        CYAN = ""
        GREEN = ""
        YELLOW = ""
        RED = ""
        GRAY = ""
        border_color = ""
    else:
        RESET = "\033[0m"
        BOLD = "\033[1m"
        DIM = "\033[2m"
        CYAN = "\033[36m"
        GREEN = "\033[32m"
        YELLOW = "\033[33m"
        RED = "\033[31m"
        GRAY = "\033[90m"
        border_color = GRAY

    TL, TR = "╭", "╮"
    BL, BR = "╰", "╯"
    HL, VL = "─", "│"
    SEP_L, SEP_R = "├", "┤"

    inner_width = width - 4  # Margins of 2 chars on each side: "│ " and " │"

    if error_msg:

        def make_centered_line(text_visible, text_styled):
            pad_total = inner_width - text_visible
            if pad_total < 0:
                pad_total = 0
            pad_left = pad_total // 2
            pad_right = pad_total - pad_left
            return f"{border_color}{VL}{RESET}{' ' * (pad_left + 1)}{text_styled}{' ' * (pad_right + 1)}{border_color}{VL}{RESET}"

        lines = []
        lines.append(f"{border_color}{TL}{HL * (width - 2)}{TR}{RESET}")

        name_display = name
        if len(name) > inner_width:
            name_display = "..." + name[-(inner_width - 3) :]
        name_styled = f"{BOLD}{CYAN}{name_display}{RESET}"
        lines.append(
            f"{border_color}{VL}{RESET} {name_styled}{' ' * (inner_width - len(name_display))} {border_color}{VL}{RESET}"
        )

        lines.append(f"{border_color}{SEP_L}{HL * (width - 2)}{SEP_R}{RESET}")
        lines.append(
            f"{border_color}{VL}{RESET}{' ' * (inner_width + 2)}{border_color}{VL}{RESET}"
        )

        skipped_visible = "SKIPPED (TOO LARGE)"
        skipped_styled = (
            f"{YELLOW}{BOLD}{skipped_visible}{RESET}"
            if not no_color
            else skipped_visible
        )
        lines.append(make_centered_line(len(skipped_visible), skipped_styled))

        msg_visible = error_msg
        msg_styled = f"{DIM}{msg_visible}{RESET}" if not no_color else msg_visible
        lines.append(make_centered_line(len(msg_visible), msg_styled))

        lines.append(
            f"{border_color}{VL}{RESET}{' ' * (inner_width + 2)}{border_color}{VL}{RESET}"
        )
        lines.append(f"{border_color}{BL}{HL * (width - 2)}{BR}{RESET}")
        return lines

    def make_line(label, value_styled, value_visible):
        label_visible = label + " "
        label_styled = f"{DIM}{label}{RESET} "

        total_visible = len(label_visible) + len(value_visible)
        pad_len = inner_width - total_visible
        if pad_len < 0:
            pad_len = 0

        return f"{border_color}{VL}{RESET} {label_styled}{value_styled}{' ' * pad_len} {border_color}{VL}{RESET}"

    lines = []

    # Top border
    lines.append(f"{border_color}{TL}{HL * (width - 2)}{TR}{RESET}")

    # Name line
    name_display = name
    if len(name) > inner_width:
        name_display = "..." + name[-(inner_width - 3) :]
    name_styled = f"{BOLD}{CYAN}{name_display}{RESET}"

    lines.append(
        f"{border_color}{VL}{RESET} {name_styled}{' ' * (inner_width - len(name_display))} {border_color}{VL}{RESET}"
    )

    # Separator
    lines.append(f"{border_color}{SEP_L}{HL * (width - 2)}{SEP_R}{RESET}")

    # Parse metrics
    parsed_bytes = metrics.get("Parsed bytes", "N/A")
    duration_raw = metrics.get("Duration", "N/A")
    throughput = metrics.get("Throughput", "N/A")
    nodes_alloc = metrics.get("Nodes allocated", "N/A")

    # Format Duration
    duration_str = duration_raw
    if "ns" in duration_raw:
        try:
            ns_val = int(duration_raw.replace("ns", "").replace(",", "").strip())
            if ns_val >= 1_000_000_000:
                duration_str = f"{ns_val / 1_000_000_000:.3f} s"
            elif ns_val >= 1_000_000:
                duration_str = f"{ns_val / 1_000_000:.2f} ms"
            elif ns_val >= 1_000:
                duration_str = f"{ns_val / 1_000:.1f} µs"
            else:
                duration_str = f"{ns_val} ns"
        except ValueError:
            pass

    bytes_styled = f"{BOLD}{parsed_bytes}{RESET}"
    duration_styled = f"{BOLD}{duration_str}{RESET}"
    throughput_styled = f"{BOLD}{throughput}{RESET}"

    # Highlight nodes allocated (0 is green, non-zero is yellow/orange)
    nodes_visible = str(nodes_alloc)
    try:
        nodes_num = int(nodes_alloc.replace(",", "").strip())
        if nodes_num == 0:
            nodes_styled = f"{GREEN}{nodes_visible}{RESET}"
        else:
            nodes_styled = f"{YELLOW}{BOLD}{nodes_visible}{RESET}"
    except ValueError:
        nodes_styled = f"{BOLD}{nodes_visible}{RESET}"

    lines.append(make_line("Parsed bytes:", bytes_styled, parsed_bytes))
    lines.append(make_line("Duration:", duration_styled, duration_str))
    lines.append(make_line("Throughput:", throughput_styled, throughput))
    lines.append(make_line("Nodes alloc:", nodes_styled, nodes_visible))

    # Bottom border
    lines.append(f"{border_color}{BL}{HL * (width - 2)}{BR}{RESET}")
    return lines


def get_terminal_cols(width, spacing=2):
    """
    Computes the maximum columns of cards that can fit in the terminal.
    """
    try:
        terminal_columns = os.get_terminal_size().columns
    except OSError:
        terminal_columns = 80
    cols = (terminal_columns + spacing) // (width + spacing)
    return max(1, cols)


def print_grid(cards, cols=None, spacing=2):
    """
    Renders multiple cards in a grid side-by-side.
    If cols is None, it is automatically calculated based on screen width.
    """
    if not cards:
        return
    if cols is None:
        import re

        ansi_escape = re.compile(r"\x1b\[[0-9;]*m")
        card_width = len(ansi_escape.sub("", cards[0][0]))
        cols = get_terminal_cols(card_width, spacing)
    for i in range(0, len(cards), cols):
        row_cards = cards[i : i + cols]
        num_lines = len(row_cards[0])
        for line_idx in range(num_lines):
            row_line = (" " * spacing).join(card[line_idx] for card in row_cards)
            print(row_line)
        print()


def draw_card_in_row(card_lines, col_idx, width=34, spacing=2):
    """
    Draws card_lines at the horizontal offset determined by col_idx,
    assuming the cursor is currently at the top-left of the row.
    """
    col_offset = col_idx * (width + spacing)
    for line_idx, line in enumerate(card_lines):
        move_down = f"\033[{line_idx}B" if line_idx > 0 else ""
        move_up = f"\033[{line_idx}A" if line_idx > 0 else ""
        move_to_col = f"\r\033[{col_offset}C" if col_offset > 0 else "\r"
        sys.stdout.write(f"{move_down}{move_to_col}{line}{move_up}")
    sys.stdout.flush()


def format_placeholder_card(name, width=34, no_color=False):
    """
    Formats a placeholder card with 'Running...' text.
    """
    if no_color:
        RESET = ""
        BOLD = ""
        DIM = ""
        CYAN = ""
        border_color = ""
    else:
        RESET = "\033[0m"
        BOLD = "\033[1m"
        DIM = "\033[2m"
        CYAN = "\033[36m"
        border_color = "\033[90m"

    TL, TR = "╭", "╮"
    BL, BR = "╰", "╯"
    HL, VL = "─", "│"
    SEP_L, SEP_R = "├", "┤"

    inner_width = width - 4

    lines = []
    lines.append(f"{border_color}{TL}{HL * (width - 2)}{TR}{RESET}")

    name_display = name
    if len(name) > inner_width:
        name_display = "..." + name[-(inner_width - 3) :]
    name_styled = f"{BOLD}{CYAN}{name_display}{RESET}"
    lines.append(
        f"{border_color}{VL}{RESET} {name_styled}{' ' * (inner_width - len(name_display))} {border_color}{VL}{RESET}"
    )

    lines.append(f"{border_color}{SEP_L}{HL * (width - 2)}{SEP_R}{RESET}")

    running_visible = "Running..."
    running_styled = f"{DIM}{running_visible}{RESET}"
    pad_len = inner_width - len(running_visible)
    lines.append(
        f"{border_color}{VL}{RESET} {running_styled}{' ' * pad_len} {border_color}{VL}{RESET}"
    )

    for _ in range(3):
        lines.append(
            f"{border_color}{VL}{RESET} {' ' * inner_width} {border_color}{VL}{RESET}"
        )

    lines.append(f"{border_color}{BL}{HL * (width - 2)}{BR}{RESET}")
    return lines


def run_benchmark_suite(name, parser_type, inputs, mode, gen_opts, args):
    """
    Runs parser generator and compiles/runs benchmarks for all input files.
    """
    parser_types = [parser_type] if isinstance(parser_type, str) else parser_type

    # 1. Run parser generator command for all parser types
    for p_type in parser_types:
        gen_command_str = f"{GENERATOR_COMMAND}{name}"
        cmd_args = (
            shlex.split(gen_command_str) + ["--parser-type", p_type] + list(gen_opts)
        )
        try:
            subprocess.run(
                cmd_args,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            print(
                f"\n\033[31mError running parser generator command:\033[0m {' '.join(cmd_args)}"
            )
            print(f"\033[33mCommand Output:\033[0m\n{e.stdout}")
            sys.exit(1)

    # Extract input size from gen_opts (defaults to None if not specified)
    input_size = None
    if "--input-size" in gen_opts:
        try:
            size_idx = gen_opts.index("--input-size")
            input_size = int(gen_opts[size_idx + 1])
        except (ValueError, IndexError):
            pass

    RESET = "" if args.no_color else "\033[0m"
    BOLD = "" if args.no_color else "\033[1m"
    CYAN = "" if args.no_color else "\033[36m"
    MAGENTA = "" if args.no_color else "\033[35m"
    GRAY = "" if args.no_color else "\033[90m"

    if mode == "Debug":
        print(
            f"\n{GRAY}------------------------------------------------------------{RESET}"
        )
        print(
            f"{MAGENTA}{name}{RESET} --parser-type {CYAN}{'/'.join(parser_types)}{RESET} {BOLD}{' '.join(gen_opts)}{RESET}"
        )
        print(
            f"{GRAY}------------------------------------------------------------{RESET}"
        )
        # Verification run in Debug mode
        for p_type in parser_types:
            target = f"{p_type.lower()}-{name}"
            for input_file in inputs:
                file_path = input_file
                if input_size is not None and os.path.exists(file_path):
                    if os.path.getsize(file_path) >= (2**input_size):
                        continue

                cmd = [
                    "zig",
                    "build",
                    "-Doptimize=Debug",
                    target,
                    "--",
                    input_file,
                    "--verbosity",
                    "0",
                    "--iterations",
                    "1",
                ]
                try:
                    subprocess.run(
                        cmd,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        check=True,
                    )
                except subprocess.CalledProcessError as e:
                    print(
                        f"\n\033[31mError building/running {target} in Debug mode for {input_file}:\033[0m"
                    )
                    print(f"\033[33mCommand Output:\033[0m\n{e.stdout}")
                    sys.exit(1)
        return

    # ReleaseFast mode - print beautiful headers and cards grid

    # Determine if we should render interactively
    is_interactive = sys.stdout.isatty() and not args.no_color

    # Determine the number of columns to use dynamically
    cols = get_terminal_cols(args.width, spacing=2)

    # Combine inputs and parser_types into grid items
    grid_items = []
    for input_file in inputs:
        for p_type in parser_types:
            grid_items.append((input_file, p_type))

    for i in range(0, len(grid_items), cols):
        row_items = grid_items[i : i + cols]
        row_cards = []

        # If interactive, pre-allocate space for the row
        if is_interactive:
            for _ in range(8):
                print()
            sys.stdout.write("\033[8A\033[1G")
            sys.stdout.flush()

        for col_idx, (input_file, p_type) in enumerate(row_items):
            card_title = f"[{p_type}] {input_file}"
            # Check if file size >= 2^input_size
            file_path = input_file
            is_too_large = False
            file_size = 0
            if os.path.exists(file_path):
                file_size = os.path.getsize(file_path)
                if input_size is not None and file_size >= (2**input_size):
                    is_too_large = True

            # Calculate iterations proportional to the input file size
            # Total parsed bytes target is ~100MB (100 * 1024 * 1024 bytes)
            target_bytes = 200 * 1024 * 1024
            if file_size > 0:
                iterations = max(1, int(target_bytes / file_size))
            else:
                iterations = 200000  # fallback

            # Render placeholder only when this specific card starts running and is not skipped
            if is_interactive and not is_too_large:
                placeholder = format_placeholder_card(
                    card_title, width=args.width, no_color=args.no_color
                )
                draw_card_in_row(placeholder, col_idx, width=args.width, spacing=2)

            if is_too_large:
                msg = f"Size >= 2^{input_size}"
                card_lines = format_card(
                    card_title,
                    {},
                    width=args.width,
                    no_color=args.no_color,
                    error_msg=msg,
                )
                if is_interactive:
                    draw_card_in_row(card_lines, col_idx, width=args.width, spacing=2)
                else:
                    row_cards.append(card_lines)
                continue

            target = f"{p_type.lower()}-{name}"
            cmd = [
                "zig",
                "build",
                "-Doptimize=ReleaseFast",
                target,
                "--",
                input_file,
                "--verbosity",
                "0",
                "--iterations",
                str(iterations),
            ]

            try:
                result = subprocess.run(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    check=True,
                )
                metrics = parse_zig_output(result.stdout)
                card_lines = format_card(
                    card_title, metrics, width=args.width, no_color=args.no_color
                )

                if is_interactive:
                    draw_card_in_row(card_lines, col_idx, width=args.width, spacing=2)
                else:
                    row_cards.append(card_lines)
            except subprocess.CalledProcessError as e:
                if is_interactive:
                    sys.stdout.write("\033[8B\033[1G")
                    sys.stdout.flush()
                print(
                    f"\n\033[31mError running benchmark command for {input_file} ({p_type}):\033[0m"
                )
                print(f"\033[33mCommand Output:\033[0m\n{e.stdout}")
                sys.exit(1)

        if is_interactive:
            # Move cursor past the completed cards row
            sys.stdout.write("\033[8B\033[1G")
            print()  # Row separator space
            sys.stdout.flush()
        else:
            print_grid(row_cards, cols=cols)


def get_parser_types_for_language(lang_name, args):
    lang_dir = os.path.join("languages", lang_name)
    available = []
    for p_type in ["LL", "LR"]:
        grm_file = os.path.join(lang_dir, f"{p_type.lower()}.grm")
        if os.path.exists(grm_file):
            available.append(p_type)
    if args.parser_type:
        if args.parser_type in available:
            return [args.parser_type]
        else:
            return []
    return available


def grammar_benchmark(mode, gen_opts, args):
    inputs = [
        "languages/grammar/ll.grm",
        "languages/grammar/lr.grm",
        "languages/json/ll.grm",
        "languages/test-ll/ll.grm",
        "languages/test-ll1/ll.grm",
    ]
    parser_types = get_parser_types_for_language("grammar", args)
    run_benchmark_suite("grammar", parser_types, inputs, mode, gen_opts, args)


def json_benchmark(mode, gen_opts, args):
    inputs = [
        "languages/json/sample-code.json",
        "languages/json/large-sample-code.json",
    ]
    parser_types = get_parser_types_for_language("json", args)
    run_benchmark_suite("json", parser_types, inputs, mode, gen_opts, args)


def augmented_json_benchmark(mode, gen_opts, args):
    inputs = [
        "languages/json/sample-code.json",
        "languages/json/large-sample-code.json",
        "languages/augmented-json/large-sample-code-interweaved.json",
    ]
    parser_types = get_parser_types_for_language("augmented-json", args)
    run_benchmark_suite("json", parser_types, inputs, mode, gen_opts, args)


def test_ll_benchmark(mode, gen_opts, args):
    inputs = [
        "languages/test-ll/sample-code",
        "languages/test-ll/large-sample-code",
    ]
    parser_types = get_parser_types_for_language("test-ll", args)
    run_benchmark_suite("test-ll", parser_types, inputs, mode, gen_opts, args)


def test_ll1_benchmark(mode, gen_opts, args):
    inputs = [
        "languages/test-ll1/sample-code",
    ]
    parser_types = get_parser_types_for_language("test-ll1", args)
    run_benchmark_suite("test-ll1", parser_types, inputs, mode, gen_opts, args)


def flat_json_benchmark(mode, gen_opts, args):
    inputs = [
        "languages/json/sample-code.json",
        "languages/json/large-sample-code.json",
    ]
    parser_types = get_parser_types_for_language("flat_json", args)
    run_benchmark_suite("flat_json", parser_types, inputs, mode, gen_opts, args)


def run_all_modes(benchmark_fn, args):
    """
    Iterates through all feature modes, input sizes, and optimize modes.
    """
    ast_modes = ["--no-ast", "--no-procedures"]
    if args.no_ast:
        ast_modes = ["--no-ast"]
    elif args.with_ast or args.no_procedures:
        ast_modes = ["--no-procedures"]

    sizes = [16, 32]
    if args.input_size is not None:
        sizes = [args.input_size]

    term_asts = ["--no-ast-for-terminals", "--ast-for-terminals"]
    if args.ast_for_terminals:
        term_asts = ["--ast-for-terminals"]
    elif args.no_ast_for_terminals:
        term_asts = ["--no-ast-for-terminals"]

    modes = ["Debug", "ReleaseFast"]
    if args.debug:
        modes = ["Debug"]
    elif args.release_fast:
        modes = ["ReleaseFast"]

    for ast_mode in ast_modes:
        for size in sizes:
            for term_ast in term_asts:
                if ast_mode == "--no-ast" and term_ast == "--ast-for-terminals":
                    continue
                for mode in modes:
                    benchmark_fn(
                        mode, [ast_mode, "--input-size", str(size), term_ast], args
                    )


BENCHMARKS = {
    "grammar": grammar_benchmark,
    "augmented-json": augmented_json_benchmark,
    "json": json_benchmark,
    "flat-json": flat_json_benchmark,
    "test-ll": test_ll_benchmark,
    "test-ll1": test_ll1_benchmark,
}


def main():
    parser = argparse.ArgumentParser(
        description="Parser Generator Benchmarking Grid Runner"
    )
    parser.add_argument(
        "--width",
        type=int,
        default=28,
        help="Width of each card in characters (default: 28)",
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable colored output and progress carriage returns",
    )
    parser.add_argument(
        "--benchmark",
        default="grammar",
        help="Benchmark to run (default: grammar). Accepts any language name; use --input to specify input files for languages not in the built-in list.",
    )
    parser.add_argument(
        "--input",
        nargs="+",
        dest="inputs",
        help="Input files to benchmark (paths relative to languages/)",
    )
    parser.add_argument(
        "--parser-type",
        choices=["LL", "LR", "GLR"],
        help="Restrict benchmark to a specific parser type (LL, LR, GLR)",
    )
    parser.add_argument(
        "--no-ast",
        action="store_true",
        help="Fix AST mode to --no-ast",
    )
    parser.add_argument(
        "--with-ast",
        action="store_true",
        help="Fix AST mode to --no-procedures (AST enabled)",
    )
    parser.add_argument(
        "--no-procedures",
        action="store_true",
        help="Fix AST mode to --no-procedures",
    )
    parser.add_argument(
        "--input-size",
        type=int,
        choices=[16, 32],
        help="Fix input size (16 or 32)",
    )
    parser.add_argument(
        "--ast-for-terminals",
        action="store_true",
        help="Fix terminal AST mode to --ast-for-terminals",
    )
    parser.add_argument(
        "--no-ast-for-terminals",
        action="store_true",
        help="Fix terminal AST mode to --no-ast-for-terminals",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Fix build optimize mode to Debug",
    )
    parser.add_argument(
        "--release-fast",
        action="store_true",
        help="Fix build optimize mode to ReleaseFast",
    )

    args = parser.parse_args()

    if args.benchmark in BENCHMARKS and not args.inputs:
        benchmark_fn = BENCHMARKS[args.benchmark]
    else:
        lang = args.benchmark
        if not args.inputs:
            parser.error(
                f"--input is required for benchmark '{lang}' (not a built-in benchmark)"
            )
        inputs = list(args.inputs)

        def benchmark_fn(mode, gen_opts, a, _lang=lang, _inputs=inputs):
            parser_types = get_parser_types_for_language(_lang, a)
            if not parser_types:
                print(f"\033[31mNo parser types found for '{_lang}'\033[0m")
                sys.exit(1)
            run_benchmark_suite(_lang, parser_types, _inputs, mode, gen_opts, a)

    try:
        run_all_modes(benchmark_fn, args)
    except KeyboardInterrupt:
        print("\n\033[31mBenchmark suite cancelled by user.\033[0m")
        sys.exit(1)


if __name__ == "__main__":
    main()
