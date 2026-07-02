const std = @import("std");
const galley = @import("galley");
const ll_generator = @import("ll_generator");
const lr_generator = @import("lr_generator");
const data_structures = galley.data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

pub const indentation_syntax = false;

pub const SymbolKind = enum {
    variable,
    terminal,
    generative_terminal,
};

pub const SymbolRef = struct {
    id: []const u8,
    kind: SymbolKind,
    procedures: []const []const u8,
};

pub const RightHandSide = struct {
    symbols: []const SymbolRef,
    procedures: []const []const u8,
};

pub const Rule = struct {
    header: []const u8,
    procedures: []const []const u8,
    right_hand_sides: []const RightHandSide,
};

pub const Grammar = struct {
    rules: []const Rule,
};

pub const Payload = struct {
    grammar: ?*Grammar = null,
};

var last_grammar: ?*Grammar = null;

const MutableRightHandSide = struct {
    symbols: std.ArrayList(SymbolRef) = .empty,
    procedures: std.ArrayList([]const u8) = .empty,
};

const MutableRule = struct {
    header: []const u8,
    procedures: std.ArrayList([]const u8) = .empty,
    right_hand_sides: std.ArrayList(MutableRightHandSide) = .empty,
};

const ParseState = struct {
    rules: std.ArrayList(MutableRule) = .empty,
    current_rule: ?usize = null,
};

pub fn reduction(args: *ProcedureArguments) void {
    if (args.node) |node_address| {
        const node = args.context.node_allocator.at(node_address);
        const end = args.context.pos();
        if (end >= node.text_start) {
            node.text_length = end - node.text_start;
        }
    }
}

pub fn reduction_Start(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        const node = args.context.node_allocator.at(node_address);
        const end = args.context.pos();
        if (end >= node.text_start) {
            node.text_length = end - node.text_start;
        }
        const source = args.context.get_text_slice(node.text_start, node.text_length);
        const grammar = try parseGrammar(args.context.arena_allocator, source);
        node.payload.grammar = grammar;
        last_grammar = grammar;
        try emitParserForInputPath(args.context, grammar);
    }

    if (args.context.verbosityLevel() > 0)
        std.debug.print("Parsed Galley grammar successfully.\n", .{});
}

pub fn grammarFromContext(context: *data_structures.Context) ?*Grammar {
    if (last_grammar) |grammar| return grammar;

    var index: usize = 0;
    while (index < context.node_allocator.counter) : (index += 1) {
        const node = context.node_allocator.at(@intCast(index));
        if (node.payload.grammar) |grammar| return grammar;
    }
    return null;
}

pub fn emitLlParser(grammar: *const Grammar, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    try ll_generator.emitParser(allocator, grammar, writer);
}

pub fn emitLlParserWithOptions(grammar: *const Grammar, allocator: std.mem.Allocator, writer: *std.Io.Writer, options: ll_generator.Options) !void {
    try ll_generator.emitParserWithOptions(allocator, grammar, writer, options);
}

pub fn emitLlParserFromContext(context: *data_structures.Context, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    const grammar = grammarFromContext(context) orelse return error.GrammarModelMissing;
    try emitLlParserWithOptions(grammar, allocator, writer, generatorOptionsFromContext(context));
}

pub fn emitLrParser(grammar: *const Grammar, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    try lr_generator.emitParser(allocator, grammar, writer);
}

pub fn emitLrParserWithOptions(grammar: *const Grammar, allocator: std.mem.Allocator, writer: *std.Io.Writer, options: lr_generator.Options) !void {
    try lr_generator.emitParserWithOptions(allocator, grammar, writer, options);
}

pub fn emitLrParserFromContext(context: *data_structures.Context, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    const grammar = grammarFromContext(context) orelse return error.GrammarModelMissing;
    try emitLrParserWithOptions(grammar, allocator, writer, lrGeneratorOptionsFromContext(context));
}

fn emitParserForInputPath(context: *data_structures.Context, grammar: *const Grammar) !void {
    const input_path = context.runtime().input_path orelse return;
    const parser_type: enum { ll, lr } = if (std.mem.endsWith(u8, input_path, "/ll.grm") or std.mem.eql(u8, input_path, "ll.grm"))
        .ll
    else if (std.mem.endsWith(u8, input_path, "/lr.grm") or std.mem.eql(u8, input_path, "lr.grm"))
        .lr
    else
        return;

    const dir_path = std.fs.path.dirname(input_path) orelse ".";
    const output_file = switch (parser_type) {
        .ll => "_ll-parser.zig",
        .lr => "_lr-parser.zig",
    };
    const output_path = try std.fs.path.join(context.arena_allocator, &.{ dir_path, output_file });

    var output = try std.Io.Dir.cwd().createFile(context.runtime().io, output_path, .{ .truncate = true });
    defer output.close(context.runtime().io);

    var buffer: [8192]u8 = undefined;
    var file_writer = output.writer(context.runtime().io, &buffer);
    switch (parser_type) {
        .ll => try emitLlParserWithOptions(grammar, context.arena_allocator, &file_writer.interface, generatorOptionsFromContext(context)),
        .lr => try emitLrParserWithOptions(grammar, context.arena_allocator, &file_writer.interface, lrGeneratorOptionsFromContext(context)),
    }
    try file_writer.interface.flush();
}

fn generatorOptionsFromContext(context: *data_structures.Context) ll_generator.Options {
    return .{
        .with_ast = context.runtime().language_options.with_ast,
        .with_procedures = context.runtime().language_options.with_procedures,
        .ast_for_terminals = context.runtime().language_options.ast_for_terminals,
        .input_size = context.runtime().language_options.input_size,
    };
}

fn lrGeneratorOptionsFromContext(context: *data_structures.Context) lr_generator.Options {
    return .{
        .with_ast = context.runtime().language_options.with_ast,
        .with_procedures = context.runtime().language_options.with_procedures,
        .ast_for_terminals = context.runtime().language_options.ast_for_terminals,
        .input_size = context.runtime().language_options.input_size,
    };
}

pub fn parseGrammar(allocator: std.mem.Allocator, source: []const u8) !*Grammar {
    var state = ParseState{};

    var line_iterator = std.mem.splitScalar(u8, source, '\n');
    while (line_iterator.next()) |raw_line| {
        const line_without_cr = std.mem.trimEnd(u8, raw_line, "\r");
        const line = std.mem.trimEnd(u8, line_without_cr, " \t");

        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, line, " \t"), "#")) continue;

        if (line[0] == '|') {
            if (state.current_rule == null) return error.RightHandSideWithoutRule;
            try parseRightHandSideLine(allocator, &state, line[1..]);
        } else {
            try parseRuleHeader(allocator, &state, line);
        }
    }

    if (state.rules.items.len == 0) return error.EmptyGrammar;

    const immutable_rules = try allocator.alloc(Rule, state.rules.items.len);
    for (state.rules.items, 0..) |*mutable_rule, rule_index| {
        const immutable_right_hand_sides = try allocator.alloc(RightHandSide, mutable_rule.right_hand_sides.items.len);
        for (mutable_rule.right_hand_sides.items, 0..) |*mutable_rhs, rhs_index| {
            immutable_right_hand_sides[rhs_index] = .{
                .symbols = try mutable_rhs.symbols.toOwnedSlice(allocator),
                .procedures = try mutable_rhs.procedures.toOwnedSlice(allocator),
            };
        }

        immutable_rules[rule_index] = .{
            .header = mutable_rule.header,
            .procedures = try mutable_rule.procedures.toOwnedSlice(allocator),
            .right_hand_sides = immutable_right_hand_sides,
        };
    }

    const grammar = try allocator.create(Grammar);
    grammar.* = .{ .rules = immutable_rules };
    return grammar;
}

fn parseRuleHeader(allocator: std.mem.Allocator, state: *ParseState, line: []const u8) !void {
    var parsed = try splitProcedures(allocator, line);
    defer parsed.procedures.deinit(allocator);

    if (parsed.id.len == 0) return error.EmptyRuleHeader;
    if (!isVariableId(parsed.id)) return error.InvalidRuleHeader;

    var rule = MutableRule{ .header = try allocator.dupe(u8, parsed.id) };
    for (parsed.procedures.items) |procedure| {
        try rule.procedures.append(allocator, try allocator.dupe(u8, procedure));
    }

    try state.rules.append(allocator, rule);
    state.current_rule = state.rules.items.len - 1;
}

fn parseRightHandSideLine(allocator: std.mem.Allocator, state: *ParseState, line: []const u8) !void {
    const current_rule_index = state.current_rule orelse return error.RightHandSideWithoutRule;
    const trimmed = if (line.len > 0 and line[0] == ' ') line[1..] else line;
    const procedure_text, const symbol_text = splitRuleProcedures(trimmed);

    var rhs = MutableRightHandSide{};
    try appendProcedures(allocator, &rhs.procedures, procedure_text);

    var tokens = try tokenizeLine(allocator, symbol_text);
    defer tokens.deinit(allocator);

    for (tokens.items) |token| {
        var parsed = try splitProcedures(allocator, token);
        defer parsed.procedures.deinit(allocator);

        var symbol = SymbolRef{
            .id = try decodeEscapes(allocator, parsed.id),
            .kind = classifySymbol(parsed.id),
            .procedures = undefined,
        };

        const procedures = try allocator.alloc([]const u8, parsed.procedures.items.len);
        for (parsed.procedures.items, 0..) |procedure, index| {
            procedures[index] = try allocator.dupe(u8, procedure);
        }
        symbol.procedures = procedures;

        try rhs.symbols.append(allocator, symbol);
    }

    try state.rules.items[current_rule_index].right_hand_sides.append(allocator, rhs);
}

const ProcedureSplit = struct {
    id: []const u8,
    procedures: std.ArrayList([]const u8) = .empty,
};

fn splitProcedures(allocator: std.mem.Allocator, text: []const u8) !ProcedureSplit {
    if (text.len > 0 and (text[0] == '"' or text[0] == '\'')) {
        return .{ .id = text };
    }

    const first_at = std.mem.indexOfScalar(u8, text, '@') orelse {
        return .{ .id = text };
    };

    var result = ProcedureSplit{ .id = text[0..first_at] };
    var iterator = std.mem.splitScalar(u8, text[first_at + 1 ..], '@');
    while (iterator.next()) |procedure| {
        if (procedure.len == 0) return error.EmptyProcedureName;
        if (!isLowercaseProcedureName(procedure)) return error.InvalidProcedureName;
        try result.procedures.append(allocator, procedure);
    }
    return result;
}

fn splitRuleProcedures(text: []const u8) struct { []const u8, []const u8 } {
    if (text.len == 0) return .{ "", "" };
    if (text[0] != '@') return .{ "", text };

    const space_index = std.mem.indexOfScalar(u8, text, ' ') orelse return .{ text, "" };
    return .{ text[0..space_index], text[space_index + 1 ..] };
}

fn appendProcedures(allocator: std.mem.Allocator, target: *std.ArrayList([]const u8), text: []const u8) !void {
    if (text.len == 0) return;
    var iterator = std.mem.splitScalar(u8, text[1..], '@');
    while (iterator.next()) |procedure| {
        if (procedure.len == 0) return error.EmptyProcedureName;
        if (!isLowercaseProcedureName(procedure)) return error.InvalidProcedureName;
        try target.append(allocator, try allocator.dupe(u8, procedure));
    }
}

fn tokenizeLine(allocator: std.mem.Allocator, line: []const u8) !std.ArrayList([]const u8) {
    var tokens = std.ArrayList([]const u8).empty;
    var current = std.ArrayList(u8).empty;
    var i: usize = 0;

    while (i < line.len) {
        const c = line[i];
        if (c == ' ') {
            if (current.items.len > 0) {
                try tokens.append(allocator, try current.toOwnedSlice(allocator));
            }
            i += 1;
        } else if (c == '"' or c == '\'') {
            const quote = c;
            const closing_char: u8 = if (quote == '"') '"' else 0x03;
            try current.append(allocator, c);
            i += 1;

            var closing_idx: ?usize = null;
            var j = i;
            while (j < line.len) : (j += 1) {
                if (line[j] == closing_char) {
                    closing_idx = j;
                    break;
                }
            }

            if (closing_idx) |end| {
                try current.appendSlice(allocator, line[i .. end + 1]);
                i = end + 1;
            } else {
                while (i < line.len and line[i] != ' ') : (i += 1) {
                    try current.append(allocator, line[i]);
                }
            }
        } else {
            try current.append(allocator, c);
            i += 1;
        }
    }

    if (current.items.len > 0) {
        try tokens.append(allocator, try current.toOwnedSlice(allocator));
    }
    return tokens;
}

fn classifySymbol(raw_id: []const u8) SymbolKind {
    if ((raw_id.len >= 2 and raw_id[0] == '"' and raw_id[raw_id.len - 1] == '"') or
        (raw_id.len >= 2 and raw_id[0] == '\'' and raw_id[raw_id.len - 1] == 0x03))
    {
        return .terminal;
    }
    if (isVariableId(raw_id)) return .variable;
    return .generative_terminal;
}

fn isVariableId(id: []const u8) bool {
    if (id.len == 0) return false;
    const start: usize = if (id[0] == '_') 1 else 0;
    if (start >= id.len) return false;
    if (!std.ascii.isUpper(id[start])) return false;
    for (id[start + 1 ..]) |char| {
        if (!std.ascii.isAlphanumeric(char) and char != '_') return false;
    }
    return true;
}

fn isLowercaseProcedureName(id: []const u8) bool {
    for (id) |char| {
        if (!(char >= 'a' and char <= 'z') and char != '_') return false;
    }
    return true;
}

fn decodeEscapes(allocator: std.mem.Allocator, raw_id: []const u8) ![]const u8 {
    const unquoted = if ((raw_id.len >= 2 and raw_id[0] == '"' and raw_id[raw_id.len - 1] == '"') or
        (raw_id.len >= 2 and raw_id[0] == '\'' and raw_id[raw_id.len - 1] == 0x03))
        raw_id[1 .. raw_id.len - 1]
    else
        raw_id;

    var decoded = std.ArrayList(u8).empty;
    var i: usize = 0;
    while (i < unquoted.len) {
        if (unquoted[i] != '\\' or i + 1 >= unquoted.len) {
            try decoded.append(allocator, unquoted[i]);
            i += 1;
            continue;
        }

        const escaped = unquoted[i + 1];
        switch (escaped) {
            'n' => try decoded.append(allocator, '\n'),
            'r' => try decoded.append(allocator, '\r'),
            't' => try decoded.append(allocator, '\t'),
            '\\' => try decoded.append(allocator, '\\'),
            '"' => try decoded.append(allocator, '"'),
            '\'' => try decoded.append(allocator, '\''),
            'x' => {
                if (i + 3 >= unquoted.len) return error.InvalidHexEscape;
                const value = try std.fmt.parseInt(u8, unquoted[i + 2 .. i + 4], 16);
                try decoded.append(allocator, value);
                i += 4;
                continue;
            },
            else => try decoded.append(allocator, escaped),
        }
        i += 2;
    }

    return decoded.toOwnedSlice(allocator);
}
