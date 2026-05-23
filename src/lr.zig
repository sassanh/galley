const clap = @import("clap");
const root = @import("root");
const std = @import("std");

pub const procedures = @import("procedures");
pub const parse_table = @import("parse-table");
pub const read_chunk_size = 128 * 1024;

const data_structures = root.data_structures;

pub fn parse(init: std.process.Init) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                          Display this help and exit.
        \\-v, --verbosity <VERBOSITY_LEVEL>   An option parameter, which takes a value.
        \\-r, --iterations <ITERATIONS>       Repeat the parse process. Useful for benchmarking.
        \\<FILE>?
        \\
    );
    const parsers = comptime .{
        .VERBOSITY_LEVEL = clap.parsers.int(usize, 10),
        .ITERATIONS = clap.parsers.int(usize, 10),
        .FILE = clap.parsers.string,
    };
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = init.gpa,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
        const stdout = &stdout_writer.interface;

        try clap.usageToFile(init.io, .stdout(), clap.Help, &params);
        _ = try stdout.writeAll("\n\n");
        try stdout.flush();
        return clap.helpToFile(init.io, .stdout(), clap.Help, &params, .{});
    }

    const verbosity = if (res.args.verbosity) |verbosity| verbosity else 0;
    const iterations = if (res.args.iterations) |iterations| iterations else 1;

    const gpa = init.gpa;
    const arena_allocator = init.arena.allocator();
    const io = init.io;

    const program_file = if (res.positionals[0]) |path|
        try std.Io.Dir.cwd().openFile(init.io, path, .{
            .mode = .read_only,
            .lock = .exclusive,
        })
    else
        std.Io.File.stdin();

    var parsed_bytes: usize = 0;

    const start = std.Io.Clock.awake.now(init.io);

    var state_stack = try std.ArrayList(u16).initCapacity(gpa, 64);
    defer state_stack.deinit(gpa);

    var semantic_stack = try std.ArrayList(?*root.data_structures.ASTNode).initCapacity(gpa, 64);
    defer semantic_stack.deinit(gpa);

    var file_buffer: [16 * 1024]u8 = undefined;
    var reader = program_file.reader(io, &file_buffer);

    var token = data_structures.Token{};
    var column_offsets = data_structures.Offsets{};
    var line_offsets = data_structures.Offsets{};

    for (0..iterations) |_| benchmark_loop: {
        try reader.seekTo(0);
        try state_stack.append(gpa, 0);

        var line: usize = 1;
        var column: usize = 1;
        var indent_width: usize = 0;
        var current_indent: usize = 0;
        var line_spaces: usize = 0;
        var is_start_of_line: bool = false;

        while (true) {
            var bytes_read = reader.interface.readSliceShort(&file_buffer) catch |err| switch (err) {
                error.ReadFailed => break,
            };

            if (bytes_read < file_buffer.len) {
                file_buffer[bytes_read] = '\x00';
                bytes_read += 1;
            }

            for (file_buffer[0..bytes_read]) |character| token_process_loop: {
                parsed_bytes += 1;
                if (verbosity > 3) {
                    std.debug.print("-- {f} {d} line spaces: {d} {}\n", .{
                        root.string_utilities.fmtString(&[_]u8{character}),
                        character,
                        line_spaces,
                        is_start_of_line,
                    });
                }

                if (is_start_of_line) {
                    if (character == ' ') {
                        line_spaces += 1;
                        continue;
                    } else {
                        is_start_of_line = false;
                        if (indent_width == 0) {
                            indent_width = line_spaces;
                        } else if (line_spaces % indent_width != 0) {
                            std.log.err("\x1b[35mIndentationError at line {d}:\n\x1b[0mInvalid number of spaces {d} which is not divisible by previousely detected indentation width of \x1b[31m\"{d}\"\x1b[0m.", .{
                                line + 1,
                                line_spaces,
                                indent_width,
                            });

                            return error.InvalidIndentation;
                        }
                        const new_indent = line_spaces / indent_width;
                        line_offsets.append(1);
                        if (new_indent == current_indent) {
                            column_offsets.append(@intCast(line_spaces + 1));
                            token.append('\n');
                        } else {
                            if (new_indent > current_indent) {
                                for (0..new_indent - current_indent) |index| {
                                    if (index != 0) {
                                        line_offsets.append(0);
                                    }
                                    column_offsets.append(@intCast(new_indent * indent_width + 1));
                                    token.append('\x01');
                                }
                            } else if (new_indent < current_indent) {
                                for (0..current_indent - new_indent) |index| {
                                    if (index != 0) {
                                        line_offsets.append(0);
                                    }
                                    column_offsets.append(@intCast(new_indent * indent_width + 1));
                                    token.append('\x02');
                                }
                            }
                            current_indent = new_indent;
                        }
                    }
                }

                if (character == '\n') {
                    line_spaces = 0;
                    is_start_of_line = true;
                    continue;
                }

                line_offsets.append(0);
                column_offsets.append(1);
                token.append(character);

                while (true) {
                    const current_state = state_stack.items[state_stack.items.len - 1];
                    if (verbosity > 1) {
                        std.debug.print("{d}:{d}:\"{f}\", Stack: [ ", .{
                            line,
                            column,
                            root.string_utilities.fmtString(token.items()),
                        });
                        for (state_stack.items, 0..) |_, index_| {
                            const index = state_stack.items.len - index_ - 1;
                            if (index_ != 0) std.debug.print(", ", .{});
                            if (index_ == 0) {
                                std.debug.print("({d})", .{state_stack.items[index]});
                            } else std.debug.print("{d}", .{state_stack.items[index]});
                        }
                        std.debug.print(" ]\n", .{});
                    }
                    const table = parse_table.action_table[current_state];

                    for (table.keys()) |key| {
                        if (key.len > token.len and std.mem.startsWith(u8, key, token.items())) {
                            break :token_process_loop;
                        }
                    }

                    const longest_prefix = if (table.getLongestPrefix(token.items())) |prefix| prefix[0] else {
                        std.log.err("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m.\nExpected tokens: \x1b[32m{f}\x1b[0m", .{
                            line,
                            column,
                            root.string_utilities.fmtString(token.items()),
                            root.string_utilities.fmtStringSlice(table.keys()),
                        });

                        return error.SyntaxError;
                    };

                    // std.debug.print("Longest prefix: \"{f}\" \"{f}\" {any}\n", .{
                    //     fmtString(longest_prefix),
                    //     fmtString(token.items()),
                    //     std.mem.eql(u8, longest_prefix, token.items()),
                    // });

                    if (std.mem.eql(u8, longest_prefix, token.items()) and token.items()[0] != '\x00') {
                        break;
                    } else if (longest_prefix.len < token.len or
                        (longest_prefix[0] == '\x00' and token.items()[0] == '\x00'))
                    {
                        if (table.get(longest_prefix)) |resolution| {
                            // std.debug.print("- {d} -> {any}\n", .{ current_state, resolution });
                            switch (resolution.type) {
                                .shift => {
                                    var last_newline: i16 = -1;
                                    line += line_offsets.sum(0, longest_prefix.len);
                                    for ("\n\x01\x02") |newline_char| {
                                        if (std.mem.lastIndexOfScalar(u8, token.items()[0..longest_prefix.len], newline_char)) |index| {
                                            if (index > last_newline) {
                                                column = column_offsets.sum(index, longest_prefix.len);
                                                last_newline = @intCast(index);
                                            }
                                        }
                                    }
                                    if (last_newline == -1) {
                                        column += column_offsets.sum(0, longest_prefix.len);
                                    }
                                    const node = try arena_allocator.create(root.data_structures.ASTNode);
                                    node.* = .{
                                        .text = try arena_allocator.dupe(u8, token.items()[0..longest_prefix.len]),
                                        .label = try std.fmt.allocPrint(arena_allocator, "text '{s}'", .{
                                            token.items()[0..longest_prefix.len],
                                        }),
                                        .variable = 0,
                                        .payload = .{},

                                        .right_hand_side_children = &[0]*root.data_structures.ASTNode{},
                                        .children = &[0]*root.data_structures.ASTNode{},
                                    };

                                    if (parse_table.is_generative_terminal[@intCast(resolution.symbol_index)]) {
                                        var args = data_structures.ProcedureArguments{
                                            .allocator = arena_allocator,
                                            .io = init.io,
                                            .verbosity = verbosity,
                                            .rule = null,
                                            .node = node,
                                        };

                                        if (parse_table.symbol_procedures[resolution.symbol_index]) |procedure_pointer| {
                                            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                                            try procedure(&args);
                                        }

                                        if (parse_table.reduction_procedure) |procedure_pointer| {
                                            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                                            try procedure(&args);
                                        }
                                    }

                                    try state_stack.append(gpa, resolution.data_index);
                                    try semantic_stack.append(gpa, node);
                                    line_offsets.pop(longest_prefix.len);
                                    column_offsets.pop(longest_prefix.len);
                                    token.pop(longest_prefix.len);
                                },
                                .reduce => {
                                    const rule = parse_table.rules[resolution.data_index];

                                    if (verbosity > 1) {
                                        std.debug.print("Reduction: {s}({d}) <~ ", .{
                                            parse_table.variables[rule.header],
                                            rule.header,
                                        });
                                        for (rule.right_hand_side, 0..) |symbol_id, i| {
                                            if (i != 0) std.debug.print(", ", .{});
                                            std.debug.print("{f}({d})", .{ root.string_utilities.fmtString(
                                                if (symbol_id == -1) "-1" else parse_table.symbols[symbol_id],
                                            ), symbol_id });
                                        }
                                        std.debug.print("\n\n", .{});
                                    }

                                    const right_hand_side = try arena_allocator.alloc(
                                        ?*root.data_structures.ASTNode,
                                        rule.right_hand_side.len,
                                    );

                                    for (0..rule.right_hand_side.len) |i| {
                                        _ = state_stack.pop();
                                        if (semantic_stack.pop()) |semantic_item| {
                                            right_hand_side[right_hand_side.len - i - 1] = semantic_item orelse null;
                                        }
                                    }
                                    var combined_text = try std.ArrayList(u8).initCapacity(arena_allocator, 256);

                                    var semantic_list_size: usize = 0;

                                    for (right_hand_side) |semantic_item| {
                                        if (semantic_item) |child| {
                                            semantic_list_size += child.augmented_length();
                                            try combined_text.appendSlice(arena_allocator, child.text);
                                        }
                                    }

                                    if (verbosity > 2) {
                                        std.debug.print("{s} text:\n {s}\n\n", .{
                                            parse_table.variables[rule.header],
                                            combined_text.items,
                                        });
                                    }

                                    const node = try arena_allocator.create(root.data_structures.ASTNode);
                                    node.* = .{
                                        .text = combined_text.items,
                                        .label = parse_table.variables[rule.header],
                                        .variable = rule.header,
                                        .payload = .{},

                                        .right_hand_side_children = right_hand_side,
                                        .children = &[0]*root.data_structures.ASTNode{},
                                    };

                                    {
                                        if (verbosity > 1) {
                                            std.debug.print("\nSemantic reduction: {s} <~ ", .{
                                                parse_table.variables[rule.header],
                                            });
                                        }
                                        var counter: usize = 0;
                                        for (right_hand_side) |semantic_item| {
                                            if (semantic_item) |semantic_item_| {
                                                if (verbosity > 1) {
                                                    var iterator = semantic_item_.iterate_augmented();
                                                    while (iterator.next()) |augmented_item| {
                                                        if (counter != 0) std.debug.print(", ", .{});
                                                        std.debug.print("{s}", .{augmented_item.label});
                                                    }

                                                    counter += 1;
                                                }

                                                try node.*.append_children(
                                                    arena_allocator,
                                                    semantic_item_.augmented_first(),
                                                );
                                            }
                                        }
                                        if (verbosity > 1) {
                                            std.debug.print("\n\n", .{});
                                        }
                                    }

                                    var args = data_structures.ProcedureArguments{
                                        .allocator = arena_allocator,
                                        .io = init.io,
                                        .verbosity = verbosity,
                                        .rule = rule,
                                        .node = node,
                                    };

                                    if (parse_table.rule_procedures[resolution.data_index]) |procedure_pointer| {
                                        const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                                        try procedure(&args);
                                    }

                                    if (parse_table.symbol_procedures[parse_table.symbol_by_variable[rule.header]]) |procedure_pointer| {
                                        const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                                        try procedure(&args);
                                    }

                                    if (parse_table.reduction_procedure) |procedure_pointer| {
                                        const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                                        try procedure(&args);
                                    }

                                    if (verbosity > 2) {
                                        std.debug.print("Procedure outcome for {s}: {f}\n", .{
                                            parse_table.variables[rule.header],
                                            root.string_utilities.fmtASTNode(args.node),
                                        });
                                    }

                                    const new_current_state = state_stack.items[state_stack.items.len - 1];
                                    if (parse_table.goto_table[new_current_state].get(rule.header)) |goto_state| {
                                        try state_stack.append(gpa, goto_state);
                                        try semantic_stack.append(gpa, args.node);
                                    } else {
                                        return error.Q;
                                    }
                                },
                                .accept => {
                                    line_offsets.pop(longest_prefix.len);
                                    column_offsets.pop(longest_prefix.len);
                                    token.pop(1);
                                    if (verbosity > 0) {
                                        std.log.info("The input file was parsed successfully!", .{});
                                    }
                                    break :benchmark_loop;
                                },
                            }
                        } else {
                            unreachable;
                        }
                    }
                }
            }
        }
    }

    if (iterations > 1) {
        const end = std.Io.Clock.awake.now(init.io);
        const duration = start.durationTo(end);
        const elapsed_ns: usize = @intCast(duration.toNanoseconds());
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(parsed_bytes)) / duration_secs;

        var buffer: [64]u8 = undefined;
        std.debug.print("Parsed bytes:  {s}\n", .{try root.string_utilities.formatFileSize(parsed_bytes, &buffer)});
        std.debug.print("Duration:      {s} ns\n", .{try root.string_utilities.formatWithThousands(elapsed_ns, &buffer)});
        std.debug.print("Throughput:    {s}/s\n", .{try root.string_utilities.formatFileSize(mbps, &buffer)});
    }
}
