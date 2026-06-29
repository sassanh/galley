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


def truncate_name(name, inner_width):
    if len(name) <= inner_width:
        return name
    if name.startswith("[") and "] " in name:
        prefix_idx = name.index("] ") + 2
        prefix = name[:prefix_idx]
        rest = name[prefix_idx:]
        avail_width = inner_width - len(prefix)
        if avail_width >= 5:
            return prefix + "..." + rest[-(avail_width - 3) :]
    return "..." + name[-(inner_width - 3) :]


def format_file_size(size_bytes):
    if size_bytes < 1024.0:
        return f"{int(size_bytes)} B"
    for unit in ["KB", "MB", "GB", "TB", "PB"]:
        size_bytes /= 1024.0
        if size_bytes < 1024.0:
            return f"{size_bytes:.2f} {unit}"
    return f"{size_bytes:.2f} PB"


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


def format_card(name, metrics, width, no_color=False, error_msg=None):
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

        name_display = truncate_name(name, inner_width)
        name_styled = f"{BOLD}{CYAN}{name_display}{RESET}"
        lines.append(
            f"{border_color}{VL}{RESET} {name_styled}{' ' * (inner_width - len(name_display))} {border_color}{VL}{RESET}"
        )

        lines.append(f"{border_color}{SEP_L}{HL * (width - 2)}{SEP_R}{RESET}")
        lines.append(
            f"{border_color}{VL}{RESET}{' ' * (inner_width + 2)}{border_color}{VL}{RESET}"
        )

        if error_msg == "success":
            skipped_visible = "Ran successfully"
            skipped_styled = (
                f"{GREEN}{BOLD}{skipped_visible}{RESET}"
                if not no_color
                else skipped_visible
            )
            lines.append(make_centered_line(len(skipped_visible), skipped_styled))

            parsed_bytes = metrics.get("Parsed bytes", None)
            if parsed_bytes:
                msg_visible = f"Size: {parsed_bytes}"
            else:
                msg_visible = "(No errors)"
            msg_styled = f"{DIM}{msg_visible}{RESET}" if not no_color else msg_visible
            lines.append(make_centered_line(len(msg_visible), msg_styled))
        else:
            skipped_visible = "SKIPPED (TOO LARGE)"
            skipped_styled = (
                f"{YELLOW}{BOLD}{skipped_visible}{RESET}"
                if not no_color
                else skipped_visible
            )
            lines.append(make_centered_line(len(skipped_visible), skipped_styled))

            parsed_bytes = metrics.get("Parsed bytes", None)
            if parsed_bytes:
                msg_visible = f"Size: {parsed_bytes} ({error_msg})"
            else:
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
    name_display = truncate_name(name, inner_width)
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

    file_size_visible = metrics.get("File size", "N/A")
    file_size_styled = (
        f"{BOLD}{file_size_visible}{RESET}" if not no_color else file_size_visible
    )

    lines.append(make_line("File size:", file_size_styled, file_size_visible))
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


def draw_card_in_row(card_lines, col_idx, width, spacing=2):
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


def format_placeholder_card(name, width, no_color=False, status="Running..."):
    """
    Formats a placeholder card with 'Running...' or 'Building...' text.
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

    name_display = truncate_name(name, inner_width)
    name_styled = f"{BOLD}{CYAN}{name_display}{RESET}"
    lines.append(
        f"{border_color}{VL}{RESET} {name_styled}{' ' * (inner_width - len(name_display))} {border_color}{VL}{RESET}"
    )

    lines.append(f"{border_color}{SEP_L}{HL * (width - 2)}{SEP_R}{RESET}")

    running_visible = status
    running_styled = f"{DIM}{running_visible}{RESET}"
    pad_len = inner_width - len(running_visible)
    lines.append(
        f"{border_color}{VL}{RESET} {running_styled}{' ' * pad_len} {border_color}{VL}{RESET}"
    )

    for _ in range(4):
        lines.append(
            f"{border_color}{VL}{RESET} {' ' * inner_width} {border_color}{VL}{RESET}"
        )

    lines.append(f"{border_color}{BL}{HL * (width - 2)}{BR}{RESET}")
    return lines


def format_grid_to_string(cards, cols, spacing=2):
    """
    Renders multiple cards in a grid side-by-side and returns the formatted string.
    """
    if not cards:
        return ""
    lines = []
    for i in range(0, len(cards), cols):
        row_cards = cards[i : i + cols]
        num_lines = len(row_cards[0])
        for line_idx in range(num_lines):
            row_line = (" " * spacing).join(card[line_idx] for card in row_cards)
            lines.append(row_line)
        lines.append("")
    return "\n".join(lines)


def write_result_to_file(filepath, content):
    """
    Writes content to the specified filepath, creating parent directories if needed.
    """
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)


def run_benchmark_suite(name, parser_type, inputs, gen_opts, args):
    """
    Runs parser generator and compiles/runs benchmarks for all input files.
    """
    parser_types = [parser_type] if isinstance(parser_type, str) else parser_type

    # Extract AST mode
    # Extract AST mode
    ast_mode = "default-ast"
    if "--no-ast" in gen_opts:
        ast_mode = "no-ast"
    elif "--no-procedures" in gen_opts:
        ast_mode = "no-procedures"

    # Extract input size string for path
    input_size_dir = "default-size"
    if "--input-size" in gen_opts:
        try:
            size_idx = gen_opts.index("--input-size")
            input_size_dir = f"size_{gen_opts[size_idx + 1]}"
        except (ValueError, IndexError):
            pass

    # Extract terminal AST mode
    term_ast = "default-term-ast"
    if "--no-ast-for-terminals" in gen_opts:
        term_ast = "no-ast-for-terminals"
    elif "--ast-for-terminals" in gen_opts:
        term_ast = "ast-for-terminals"

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

    # ReleaseFast mode - print beautiful headers and cards grid
    header_details = []
    if ast_mode == "no-ast":
        header_details.append("No AST")
    elif ast_mode == "no-procedures":
        header_details.append("AST (No Procedures)")
    else:
        header_details.append("AST (With Procedures)")

    if term_ast == "ast-for-terminals":
        header_details.append("Terminals in AST")
    elif term_ast == "no-ast-for-terminals":
        header_details.append("No Terminals in AST")

    if input_size is not None:
        header_details.append(f"Size Limit: 2^{input_size}")

    details_str = " | ".join(header_details)
    title_text = f" {name.upper()} BENCHMARKS ({details_str}) "
    box_width = len(title_text)
    print(f"\n{CYAN}╭{'─' * box_width}╮")
    print(f"│{title_text}│")
    print(f"╰{'─' * box_width}╯{RESET}")

    # Determine if we should render interactively
    is_interactive = sys.stdout.isatty() and not args.no_color

    # Determine the number of columns to use dynamically
    cols = get_terminal_cols(args.width, spacing=2)

    # Combine inputs and parser_types into grid items
    grid_items = []
    for input_file in inputs:
        for p_type in parser_types:
            grid_items.append((input_file, p_type))

    input_results = {}

    for i in range(0, len(grid_items), cols):
        row_items = grid_items[i : i + cols]
        row_cards = []

        # If interactive, pre-allocate space for the row
        if is_interactive:
            for _ in range(9):
                print()
            sys.stdout.write("\033[9A\033[1G")
            sys.stdout.flush()

        for col_idx, (input_file, p_type) in enumerate(row_items):
            # Check if file size >= 2^input_size
            file_path = input_file
            is_too_large = False
            file_size = 0
            if os.path.exists(file_path):
                file_size = os.path.getsize(file_path)
                if input_size is not None and file_size >= (2**input_size):
                    is_too_large = True

            card_title = f"[{p_type}] {input_file.replace('languages/', '')}"

            # Calculate iterations for calibration run (aiming for 10MB)
            calibration_iterations = 1
            if not args.validate_only:
                calibration_bytes = 30 * 1024 * 1024
                if file_size > 0:
                    calibration_iterations = max(2, int(calibration_bytes / file_size))
                else:
                    calibration_iterations = 10000

            # Render placeholder only when this specific card starts running and is not skipped
            if is_interactive and not is_too_large:
                placeholder = format_placeholder_card(
                    card_title, width=args.width, no_color=args.no_color
                )
                draw_card_in_row(placeholder, col_idx, width=args.width, spacing=2)

            if is_too_large:
                msg = f">= 2^{input_size}"
                # Collect error message for file
                input_results.setdefault(input_file, []).append(
                    (p_type, f"SKIPPED (TOO LARGE): {msg}")
                )

                metrics = {"Parsed bytes": format_file_size(file_size)}
                card_lines = format_card(
                    card_title,
                    metrics,
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

            # Render placeholder as "Building..."
            if is_interactive and not is_too_large:
                placeholder = format_placeholder_card(
                    card_title,
                    width=args.width,
                    no_color=args.no_color,
                    status="Building...",
                )
                draw_card_in_row(placeholder, col_idx, width=args.width, spacing=2)

            # Render placeholder as "Building..."
            if is_interactive and not is_too_large:
                placeholder = format_placeholder_card(
                    card_title,
                    width=args.width,
                    no_color=args.no_color,
                    status="Building...",
                )
                draw_card_in_row(placeholder, col_idx, width=args.width, spacing=2)

            # Compile in ReleaseFast mode first
            build_cmd = [
                "zig",
                "build",
                "-Doptimize=ReleaseFast",
                f"compile-{target}",
            ]
            try:
                subprocess.run(
                    build_cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    check=True,
                )
            except subprocess.CalledProcessError as compile_err:
                debug_cmd = [
                    "zig",
                    "build",
                    "-Doptimize=Debug",
                    f"compile-{target}",
                ]
                if is_interactive:
                    sys.stdout.write("\033[9B\033[1G")
                    sys.stdout.flush()
                print(
                    f"\n\033[31mError building/compiling {target} in ReleaseFast mode.\033[0m"
                    f"\n\033[33mRunning Debug mode compilation for detailed errors:\033[0m"
                )
                debug_result = subprocess.run(
                    debug_cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                )
                print(f"\033[31mError building {target} in Debug mode:\033[0m")
                print(f"\033[33mCommand Output:\033[0m\n{debug_result.stdout}")
                sys.exit(1)

            # Render placeholder as "Running..." or "Calibrating..."
            if is_interactive and not is_too_large:
                status_str = "Running..." if args.validate_only else "Calibrating..."
                placeholder = format_placeholder_card(
                    card_title,
                    width=args.width,
                    no_color=args.no_color,
                    status=status_str,
                )
                draw_card_in_row(placeholder, col_idx, width=args.width, spacing=2)

            # Run the compiled binary directly
            import sys as pysys

            binary_name = f"{target}.exe" if pysys.platform == "win32" else target
            binary_path = os.path.abspath(os.path.join("zig-out", "bin", binary_name))

            if args.validate_only:
                # Validation only - single run with 1 iteration
                run_cmd = [
                    binary_path,
                    input_file,
                    "--verbosity",
                    "0",
                    "--iterations",
                    "1",
                ]
                try:
                    subprocess.run(
                        run_cmd,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        check=True,
                    )
                    metrics = {
                        "File size": format_file_size(file_size),
                        "Parsed bytes": format_file_size(file_size),
                    }
                    input_results.setdefault(input_file, []).append(
                        (p_type, "Ran successfully (No errors)")
                    )
                    card_lines = format_card(
                        card_title,
                        metrics,
                        width=args.width,
                        no_color=args.no_color,
                        error_msg="success",
                    )
                    if is_interactive:
                        draw_card_in_row(
                            card_lines, col_idx, width=args.width, spacing=2
                        )
                    else:
                        row_cards.append(card_lines)
                except subprocess.CalledProcessError as run_err:
                    # If execution fails, compile and run in Debug mode to get detailed stack traces
                    debug_build_cmd = [
                        "zig",
                        "build",
                        "-Doptimize=Debug",
                        f"compile-{target}",
                    ]
                    subprocess.run(
                        debug_build_cmd,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                    )

                    debug_run_cmd = [
                        binary_path,
                        input_file,
                        "--verbosity",
                        "0",
                    ]
                    if is_interactive:
                        sys.stdout.write("\033[9B\033[1G")
                        sys.stdout.flush()
                    print(
                        f"\n\033[31mError running benchmark command for {input_file} ({p_type}) in ReleaseFast mode.\033[0m"
                        f"\n\033[33mRunning Debug mode execution for detailed diagnostics:\033[0m"
                    )
                    debug_run_result = subprocess.run(
                        debug_run_cmd,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                    )
                    print(
                        f"\033[31mError running {target} in Debug mode for {input_file}:\033[0m"
                    )
                    print(f"\033[33mCommand Output:\033[0m\n{debug_run_result.stdout}")
                    sys.exit(1)
            else:
                # Benchmark mode - Calibration run aiming for 10MB
                run_cmd = [
                    binary_path,
                    input_file,
                    "--verbosity",
                    "0",
                    "--iterations",
                    str(calibration_iterations),
                ]
                import time

                start_time = time.perf_counter()
                try:
                    result = subprocess.run(
                        run_cmd,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        check=True,
                    )
                    end_time = time.perf_counter()
                    python_duration = end_time - start_time
                    metrics = parse_zig_output(result.stdout)

                    # Extract duration from metrics
                    elapsed_seconds = None
                    if "Duration" in metrics:
                        try:
                            ns_val = int(
                                metrics["Duration"]
                                .replace("ns", "")
                                .replace(",", "")
                                .strip()
                            )
                            elapsed_seconds = ns_val / 1e9
                        except ValueError:
                            pass
                    if elapsed_seconds is None or elapsed_seconds <= 0:
                        elapsed_seconds = python_duration

                    # Calculate second run iterations aiming for 1.0 second runtime
                    iterations_per_sec = calibration_iterations / elapsed_seconds
                    second_iterations = max(2, int(iterations_per_sec * 1.0))

                    # Update placeholder to "Running..." for final benchmarking run
                    if is_interactive:
                        placeholder_run = format_placeholder_card(
                            card_title,
                            width=args.width,
                            no_color=args.no_color,
                            status="Running...",
                        )
                        draw_card_in_row(placeholder_run, col_idx, width=args.width, spacing=2)

                    # Run second time for 1.0 second
                    run_cmd_2 = [
                        binary_path,
                        input_file,
                        "--verbosity",
                        "0",
                        "--iterations",
                        str(second_iterations),
                    ]
                    result_2 = subprocess.run(
                        run_cmd_2,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        check=True,
                    )
                    metrics_2 = parse_zig_output(result_2.stdout)
                    metrics_2["File size"] = format_file_size(file_size)
                    if (
                        "Parsed bytes" not in metrics_2
                        or metrics_2["Parsed bytes"] == "N/A"
                    ):
                        metrics_2["Parsed bytes"] = format_file_size(file_size)

                    input_results.setdefault(input_file, []).append((p_type, metrics_2))
                    card_lines = format_card(
                        card_title, metrics_2, width=args.width, no_color=args.no_color
                    )
                    if is_interactive:
                        draw_card_in_row(
                            card_lines, col_idx, width=args.width, spacing=2
                        )
                    else:
                        row_cards.append(card_lines)

                except subprocess.CalledProcessError as run_err:
                    # If execution fails, compile and run in Debug mode to get detailed stack traces
                    debug_build_cmd = [
                        "zig",
                        "build",
                        "-Doptimize=Debug",
                        f"compile-{target}",
                    ]
                    subprocess.run(
                        debug_build_cmd,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                    )

                    debug_run_cmd = [
                        binary_path,
                        input_file,
                        "--verbosity",
                        "0",
                    ]
                    if is_interactive:
                        sys.stdout.write("\033[9B\033[1G")
                        sys.stdout.flush()
                    print(
                        f"\n\033[31mError running benchmark command for {input_file} ({p_type}) in ReleaseFast mode.\033[0m"
                        f"\n\033[33mRunning Debug mode execution for detailed diagnostics:\033[0m"
                    )
                    debug_run_result = subprocess.run(
                        debug_run_cmd,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                    )
                    print(
                        f"\033[31mError running {target} in Debug mode for {input_file}:\033[0m"
                    )
                    print(f"\033[33mCommand Output:\033[0m\n{debug_run_result.stdout}")
                    sys.exit(1)

        if is_interactive:
            # Move cursor past the completed cards row
            sys.stdout.write("\033[9B\033[1G")
            print()  # Row separator space
            sys.stdout.flush()
        else:
            print_grid(row_cards, cols=cols)

    # Write ReleaseFast results to files (one file per input)
    for input_file, results in input_results.items():
        # Get relative path of input file from languages/
        rel_input = os.path.relpath(input_file, "languages")

        # Construct file path without ReleaseFast layer
        filepath = os.path.join(
            "benchmark_results",
            "galley",
            name,
            ast_mode,
            input_size_dir,
            term_ast,
            rel_input + ".txt",
        )

        file_content = [
            f"Language: {name}",
            f"Input: {input_file}",
            f"AST Mode: {ast_mode}",
            f"Input Size Limit: {input_size_dir}",
            f"Terminal AST: {term_ast}",
            "-" * 40,
        ]

        for p_type, res in results:
            file_content.append(f"[{p_type}]")
            if isinstance(res, str):
                file_content.append(res)
            else:
                file_content.append(f"Parsed bytes: {res.get('Parsed bytes', 'N/A')}")
                file_content.append(f"Duration: {res.get('Duration', 'N/A')}")
                file_content.append(f"Throughput: {res.get('Throughput', 'N/A')}")
                file_content.append(
                    f"Nodes allocated: {res.get('Nodes allocated', 'N/A')}"
                )
            file_content.append("")

        write_result_to_file(filepath, "\n".join(file_content) + "\n")


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


def grammar_benchmark(gen_opts, args):
    inputs = [
        "languages/grammar/ll.grm",
        "languages/grammar/lr.grm",
        "languages/json/ll.grm",
        "languages/test-ll/ll.grm",
        "languages/test-ll1/ll.grm",
    ]
    parser_types = get_parser_types_for_language("grammar", args)
    run_benchmark_suite("grammar", parser_types, inputs, gen_opts, args)


def json_benchmark(gen_opts, args):
    inputs = [
        "languages/json/sample-code.json",
        "languages/json/large-sample-code.json",
    ]
    parser_types = get_parser_types_for_language("json", args)
    run_benchmark_suite("json", parser_types, inputs, gen_opts, args)


def augmented_json_benchmark(gen_opts, args):
    inputs = [
        "languages/json/sample-code.json",
        "languages/json/large-sample-code.json",
        "languages/augmented-json/large-sample-code-interweaved.json",
    ]
    parser_types = get_parser_types_for_language("augmented-json", args)
    run_benchmark_suite("augmented-json", parser_types, inputs, gen_opts, args)


def test_ll_benchmark(gen_opts, args):
    inputs = [
        "languages/test-ll/sample-code",
        "languages/test-ll/large-sample-code",
    ]
    parser_types = get_parser_types_for_language("test-ll", args)
    run_benchmark_suite("test-ll", parser_types, inputs, gen_opts, args)


def test_ll1_benchmark(gen_opts, args):
    inputs = [
        "languages/test-ll1/sample-code",
    ]
    parser_types = get_parser_types_for_language("test-ll1", args)
    run_benchmark_suite("test-ll1", parser_types, inputs, gen_opts, args)


def flat_json_benchmark(gen_opts, args):
    inputs = [
        "languages/json/sample-code.json",
        "languages/json/large-sample-code.json",
    ]
    parser_types = get_parser_types_for_language("flat_json", args)
    run_benchmark_suite("flat_json", parser_types, inputs, gen_opts, args)


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

    for ast_mode in ast_modes:
        for size in sizes:
            for term_ast in term_asts:
                if ast_mode == "--no-ast" and term_ast == "--ast-for-terminals":
                    continue
                benchmark_fn([ast_mode, "--input-size", str(size), term_ast], args)


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
        default=34,
        help="Width of each card in characters (default: 28)",
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable colored output and progress carriage returns",
    )
    parser.add_argument(
        "--language",
        default=None,
        help="Language to benchmark. If not provided, runs all built-in benchmarks sequentially. Accepts any language name; use --input to specify input files for languages not in the built-in list.",
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
        "--validate-only",
        action="store_true",
        help="Only run validation checks (iterations=1) instead of benchmarking.",
    )

    args = parser.parse_args()

    if args.language is None:
        if args.inputs:
            parser.error("--language is required when specifying --input.")

        for lang in BENCHMARKS:
            benchmark_fn = BENCHMARKS[lang]
            try:
                run_all_modes(benchmark_fn, args)
            except KeyboardInterrupt:
                print("\n\033[31mBenchmark suite cancelled by user.\033[0m")
                sys.exit(1)
    else:
        if args.language in BENCHMARKS and not args.inputs:
            benchmark_fn = BENCHMARKS[args.language]
        else:
            lang = args.language
            if not args.inputs:
                parser.error(
                    f"--input is required for benchmark '{lang}' (not a built-in benchmark)"
                )
            inputs = list(args.inputs)

            def benchmark_fn(gen_opts, a, _lang=lang, _inputs=inputs):
                parser_types = get_parser_types_for_language(_lang, a)
                if not parser_types:
                    print(f"\033[31mNo parser types found for '{_lang}'\033[0m")
                    sys.exit(1)
                run_benchmark_suite(_lang, parser_types, _inputs, gen_opts, a)

        try:
            run_all_modes(benchmark_fn, args)
        except KeyboardInterrupt:
            print("\n\033[31mBenchmark suite cancelled by user.\033[0m")
            sys.exit(1)


if __name__ == "__main__":
    main()
