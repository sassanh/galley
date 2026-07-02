const std = @import("std");
const common = @import("generator_common");

pub const Options = common.Options;
const SymbolKind = common.SymbolKind;
const Symbol = common.Symbol;
const Rule = common.Rule;
const bytesToInt = common.bytesToInt;
const emitEscapedForComment = common.emitEscapedForComment;
const emitFormatToken = common.emitFormatToken;
const emitStringLiteral = common.emitStringLiteral;
const indented = common.indented;

const Item = struct {
    variable: usize,
    rule: usize,
    head: usize,
    lookahead: usize,
};

const ActionKind = enum { shift, reduce, accept };

const Action = struct {
    terminal: usize,
    kind: ActionKind,
    state: usize = 0,
    rule: usize = 0,
};

const GotoEntry = struct {
    variable: usize,
    state: usize,
};

const State = struct {
    items: std.ArrayList(Item) = .empty,
    actions: std.ArrayList(Action) = .empty,
    gotos: std.ArrayList(GotoEntry) = .empty,
};

const Generator = struct {
    allocator: std.mem.Allocator,
    options: Options,
    symbols: std.ArrayList(Symbol) = .empty,
    variables: std.ArrayList(usize) = .empty,
    rules: std.ArrayList(Rule) = .empty,
    states: std.ArrayList(State) = .empty,
    augmented_start: usize = 0,
    eof: usize = 0,

    fn init(allocator: std.mem.Allocator, options: Options) Generator {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    fn addSymbol(self: *Generator, id: []const u8, kind: SymbolKind, procedures_: []const []const u8) !usize {
        return common.addSymbol(self.allocator, &self.symbols, &self.variables, id, kind, procedures_);
    }

    fn fromGrammar(self: *Generator, grammar: anytype) !void {
        for (grammar.rules) |rule| {
            const header = try self.addSymbol(rule.header, .variable, rule.procedures);
            for (rule.right_hand_sides, 0..) |rhs, rhs_index| {
                var generated_rule = Rule{
                    .header = header,
                    .rhs_index = try std.fmt.allocPrint(self.allocator, "{d}", .{rhs_index}),
                };
                for (rhs.symbols) |symbol| {
                    const kind: SymbolKind = switch (symbol.kind) {
                        .variable => .variable,
                        .terminal => .terminal,
                        .generative_terminal => .generative_terminal,
                    };
                    try generated_rule.rhs.append(self.allocator, try self.addSymbol(symbol.id, kind, symbol.procedures));
                }
                try self.rules.append(self.allocator, generated_rule);
            }
        }

        const original_start = self.rules.items[0].header;
        self.augmented_start = try self.addSymbol("_AugmentedStart", .variable, &.{});
        self.eof = try self.addSymbol("\x00", .end, &.{});
        var augmented_rule = Rule{ .header = self.augmented_start, .rhs_index = "0" };
        try augmented_rule.rhs.append(self.allocator, original_start);
        try augmented_rule.rhs.append(self.allocator, self.eof);
        try self.rules.append(self.allocator, augmented_rule);

        std.mem.sort(Rule, self.rules.items, self, ruleLessThan);
        try self.buildStates();
        try self.buildParseTable();
    }

    fn ruleLessThan(self: *Generator, lhs: Rule, rhs: Rule) bool {
        return common.ruleLessThan(self.symbols.items, lhs, rhs);
    }

    fn buildStates(self: *Generator) !void {
        const augmented_rule = self.ruleForHeader(self.augmented_start).?;
        var initial = State{};
        try initial.items.append(self.allocator, .{
            .variable = self.augmented_start,
            .rule = augmented_rule,
            .head = 0,
            .lookahead = self.eof,
        });
        try self.closeState(&initial);
        try self.states.append(self.allocator, initial);

        var index: usize = 0;
        while (index < self.states.items.len) : (index += 1) {
            for (0..self.symbols.items.len) |symbol_index| {
                const next = try self.gotoState(self.states.items[index], symbol_index);
                if (next.items.items.len == 0) continue;
                const existing = self.stateIndex(next) orelse blk: {
                    const new_index = self.states.items.len;
                    try self.states.append(self.allocator, next);
                    break :blk new_index;
                };
                _ = existing;
            }
        }
    }

    fn buildParseTable(self: *Generator) !void {
        for (self.states.items, 0..) |*state, state_index| {
            for (state.items.items) |item| {
                const rule = self.rules.items[item.rule];
                if (item.variable == self.augmented_start) {
                    try self.addAction(state, .{ .terminal = self.eof, .kind = .accept });
                } else if (item.head < rule.rhs.items.len) {
                    const head_symbol = rule.rhs.items[item.head];
                    if (self.symbols.items[head_symbol].kind != .variable) {
                        const target = (try self.gotoState(state.*, head_symbol));
                        const target_index = self.stateIndex(target) orelse return error.MissingShiftState;
                        try self.addAction(state, .{ .terminal = head_symbol, .kind = .shift, .state = target_index });
                    }
                } else {
                    try self.addAction(state, .{ .terminal = item.lookahead, .kind = .reduce, .rule = item.rule });
                }
            }

            for (self.variables.items) |variable| {
                const target = try self.gotoState(state.*, variable);
                if (target.items.items.len == 0) continue;
                const target_index = self.stateIndex(target) orelse return error.MissingGotoState;
                try state.gotos.append(self.allocator, .{ .variable = variable, .state = target_index });
            }

            _ = state_index;
        }
    }

    fn addAction(self: *Generator, state: *State, action: Action) !void {
        for (state.actions.items) |*existing| {
            if (existing.terminal != action.terminal) continue;
            if (existing.kind == .accept or action.kind == .accept) {
                existing.* = if (existing.kind == .accept) existing.* else action;
                return;
            }
            if (existing.kind == action.kind and existing.state == action.state and existing.rule == action.rule) return;
            return error.AmbiguousGrammar;
        }
        try state.actions.append(self.allocator, action);
    }

    fn closeState(self: *Generator, state: *State) !void {
        var index: usize = 0;
        while (index < state.items.items.len) : (index += 1) {
            const item = state.items.items[index];
            const rule = self.rules.items[item.rule];
            if (item.head >= rule.rhs.items.len) continue;
            const head_symbol = rule.rhs.items[item.head];
            if (self.symbols.items[head_symbol].kind != .variable) continue;

            var lookaheads = std.AutoHashMap(usize, void).init(self.allocator);
            defer lookaheads.deinit();
            try self.firstsAfterItem(item, &lookaheads);

            for (self.rules.items, 0..) |candidate_rule, rule_index| {
                if (candidate_rule.header != head_symbol) continue;
                var iterator = lookaheads.keyIterator();
                while (iterator.next()) |lookahead| {
                    try appendItemUnique(&state.items, self.allocator, .{
                        .variable = head_symbol,
                        .rule = rule_index,
                        .head = 0,
                        .lookahead = lookahead.*,
                    });
                }
            }
        }
        std.mem.sort(Item, state.items.items, {}, itemLessThan);
    }

    fn firstsAfterItem(self: *Generator, item: Item, out: *std.AutoHashMap(usize, void)) !void {
        const rule = self.rules.items[item.rule];
        var index = item.head + 1;
        while (index < rule.rhs.items.len) : (index += 1) {
            const symbol_index = rule.rhs.items[index];
            const symbol = self.symbols.items[symbol_index];
            if (symbol.kind == .variable) {
                try self.firstsOfVariable(symbol_index, out, null);
                if (self.nullableRule(symbol_index, null) == null) return;
            } else {
                try out.put(symbol_index, {});
                return;
            }
        }
        try out.put(item.lookahead, {});
    }

    fn firstsOfVariable(self: *Generator, variable: usize, out: *std.AutoHashMap(usize, void), visited: ?*std.AutoHashMap(usize, void)) !void {
        if (visited) |set| {
            if (set.contains(variable)) return;
        }
        var local_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer local_visited.deinit();
        if (visited) |set| {
            var it = set.keyIterator();
            while (it.next()) |entry| try local_visited.put(entry.*, {});
        }
        try local_visited.put(variable, {});

        for (self.rules.items) |rule| {
            if (rule.header != variable) continue;
            for (rule.rhs.items) |symbol_index| {
                const symbol = self.symbols.items[symbol_index];
                if (symbol.kind == .variable) {
                    try self.firstsOfVariable(symbol_index, out, &local_visited);
                    if (self.nullableRule(symbol_index, null) == null) break;
                } else {
                    try out.put(symbol_index, {});
                    break;
                }
            }
        }
    }

    fn nullableRule(self: *Generator, variable: usize, visited: ?*std.AutoHashMap(usize, void)) ?usize {
        if (visited) |set| {
            if (set.contains(variable)) return null;
        }
        var local_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer local_visited.deinit();
        if (visited) |set| {
            var it = set.keyIterator();
            while (it.next()) |entry| local_visited.put(entry.*, {}) catch unreachable;
        }
        local_visited.put(variable, {}) catch unreachable;

        for (self.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items) |symbol_index| {
                if (self.symbols.items[symbol_index].kind != .variable or self.nullableRule(symbol_index, &local_visited) == null) break;
            } else {
                return rule_index;
            }
        }
        return null;
    }

    fn gotoState(self: *Generator, state: State, symbol: usize) !State {
        var next = State{};
        for (state.items.items) |item| {
            const rule = self.rules.items[item.rule];
            if (item.head >= rule.rhs.items.len or rule.rhs.items[item.head] != symbol) continue;
            try appendItemUnique(&next.items, self.allocator, .{
                .variable = item.variable,
                .rule = item.rule,
                .head = item.head + 1,
                .lookahead = item.lookahead,
            });
        }
        if (next.items.items.len > 0) try self.closeState(&next);
        return next;
    }

    fn stateIndex(self: *Generator, state: State) ?usize {
        for (self.states.items, 0..) |candidate, index| {
            if (itemsEqual(candidate.items.items, state.items.items)) return index;
        }
        return null;
    }

    fn ruleForHeader(self: *Generator, header: usize) ?usize {
        for (self.rules.items, 0..) |rule, index| {
            if (rule.header == header) return index;
        }
        return null;
    }

    fn emit(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.writeAll(
            \\const builtin = @import("builtin");
            \\const std = @import("std");
            \\const procedures = @import("galley").procedures;
            \\const data_structures = @import("galley").data_structures;
            \\const string_utilities = @import("galley").string_utilities;
            \\
        );
        try writer.print("\npub const is_ast_enabled = {};\npub const input_size_cap = u{d};\npub const longest_terminal_length = {d};\n\n", .{ self.options.with_ast, self.options.input_size, self.longestTerminalLength() });

        try self.emitGrammarTables(writer);
        if (self.options.with_procedures and self.options.with_ast) try self.emitProcedureBoilerplate(writer);

        try writer.writeAll(
            \\const ReduceResult = struct {
            \\    variable: u16,
            \\    pops_remaining: u16,
            \\    is_accept: bool,
            \\};
            \\
            \\const SemanticStack = std.ArrayList(data_structures.ASTNode.Pointer);
            \\
        );

        for (self.states.items, 0..) |state, index| {
            try self.emitStateFunction(writer, state, index);
            try writer.writeByte('\n');
        }

        try writer.writeAll(
            \\pub fn parse(context: *data_structures.Context) !void {
            \\    var stack: SemanticStack = .empty;
            \\    defer stack.deinit(context.arena_allocator);
            \\
            \\    const result = try state_0(context, &stack);
            \\    if (!result.is_accept) {
            \\        return error.ParseError;
            \\    }
            \\
            \\    if (context.verbosityLevel() > 0) {
            \\        std.log.info("The input file was parsed successfully!", .{});
            \\    }
            \\}
            \\
        );
    }

    fn emitGrammarTables(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.writeAll("pub const symbols = &[_][]const u8{\n");
        for (self.symbols.items, 0..) |symbol, index| {
            try writer.writeAll("    ");
            try emitStringLiteral(writer, symbol.id);
            try writer.print(", // {d}\n", .{index});
        }
        try writer.writeAll("};\n\npub const is_terminal = &[_]bool{\n");
        for (self.symbols.items) |symbol| try writer.print("    {},\n", .{symbol.kind != .variable});
        try writer.writeAll("};\n\npub const is_generative_terminal = &[_]bool{\n");
        for (self.symbols.items) |symbol| try writer.print("    {},\n", .{symbol.kind == .generative_terminal});
        try writer.writeAll("};\n\npub const variables = &[_][]const u8{\n");
        for (self.variables.items) |symbol_index| {
            try writer.writeAll("    ");
            try emitStringLiteral(writer, self.symbols.items[symbol_index].id);
            try writer.writeAll(",\n");
        }
        try writer.writeAll("};\n\npub const symbol_by_variable = &[_]usize{\n");
        for (self.variables.items) |symbol_index| try writer.print("    {d},\n", .{symbol_index});
        try writer.writeAll("};\n\npub const rules = &[_]data_structures.Rule{\n");
        for (self.rules.items) |rule| {
            const variable_index = self.variableIndex(rule.header);
            try writer.print("    data_structures.Rule{{ .header = {d}, .right_hand_side = &[_]u16{{", .{variable_index});
            if (rule.rhs.items.len > 1) try writer.writeByte(' ');
            for (rule.rhs.items, 0..) |symbol_index, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.print("{d}", .{symbol_index});
            }
            if (rule.rhs.items.len > 1) try writer.writeByte(' ');
            try writer.writeAll("}, .right_hand_side_index = ");
            try emitStringLiteral(writer, rule.rhs_index);
            try writer.writeAll(" }, // ");
            try writer.writeAll(self.symbols.items[rule.header].id);
            try writer.writeByte('\n');
        }
        try writer.writeAll("};\n\n");
    }

    fn emitProcedureBoilerplate(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.print(
            \\pub const rule_procedures = rule_procedures: {{
            \\    var arr: [{d}]?*const data_structures.Procedure = .{{null}} ** {d};
            \\
            \\    for (rules, 0..) |rule, index| {{
            \\        const procedure_name = "reduction_" ++ variables[rule.header] ++ "_" ++ rule.right_hand_side_index;
            \\        if (@hasDecl(procedures, procedure_name)) {{
            \\            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name);
            \\        }}
            \\    }}
            \\
            \\    break :rule_procedures arr;
            \\}};
            \\
            \\pub const symbol_procedures = symbol_procedures: {{
            \\    var arr: [{d}]?*const data_structures.Procedure = .{{null}} ** {d};
            \\
            \\    for (symbols, 0..) |symbol, index| {{
            \\        const procedure_name = "reduction_" ++ symbol;
            \\        if (@hasDecl(procedures, procedure_name)) {{
            \\            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), symbol);
            \\        }}
            \\    }}
            \\
            \\    break :symbol_procedures arr;
            \\}};
            \\
            \\const variable_procedure_names = &[_][]const []const u8{{
            \\
        , .{ self.rules.items.len, self.rules.items.len, self.symbols.items.len, self.symbols.items.len });
        for (self.variables.items) |symbol_index| {
            const symbol = self.symbols.items[symbol_index];
            try writer.writeAll("    &[_][]const u8{");
            for (symbol.procedures.items, 0..) |procedure, i| {
                if (i != 0) try writer.writeAll(", ");
                try emitStringLiteral(writer, procedure);
            }
            try writer.writeAll("},\n");
        }
        try writer.print(
            \\}};
            \\
            \\const ProcedureSequenceNode = struct {{
            \\    procedure: *const data_structures.Procedure,
            \\    next: ?*const ProcedureSequenceNode,
            \\}};
            \\
            \\pub const variable_procedures = variable_procedures: {{
            \\    var arr: [{d}]?*const ProcedureSequenceNode = .{{null}} ** {d};
            \\
            \\    for (variable_procedure_names, 0..) |procedure_names, index| {{
            \\        var last: ?*const ProcedureSequenceNode = null;
            \\        for (procedure_names) |procedure_name| {{
            \\            last = &ProcedureSequenceNode{{
            \\                .procedure = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name),
            \\                .next = last,
            \\            }};
            \\            arr[index] = last;
            \\        }}
            \\    }}
            \\
            \\    break :variable_procedures arr;
            \\}};
            \\
            \\pub const reduction_procedure: ?*const data_structures.Procedure = if (@hasDecl(procedures, "reduction")) data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, "reduction"), "reduction") else null;
            \\
            \\
        , .{ self.variables.items.len, self.variables.items.len });
    }

    fn emitStateFunction(self: *Generator, writer: *std.Io.Writer, state: State, state_index: usize) !void {
        try writer.print("// LR parser state {d}\nfn state_{d}(context: *data_structures.Context, stack: *SemanticStack) anyerror!ReduceResult {{\n", .{ state_index, state_index });
        try writer.writeAll("    var result: ReduceResult = undefined;\n");
        if (!self.stateUsesStack(state)) {
            try writer.writeAll("    _ = stack;\n");
        }

        var entries = std.ArrayList(SwitchEntry).empty;
        for (state.actions.items, 0..) |action, action_index| {
            const terminal = self.symbols.items[action.terminal];
            for (terminal.terminals.items) |terminal_item| {
                try appendSwitchEntry(&entries, self.allocator, terminal_item, action_index);
            }
        }

        if (entries.items.len == 0) {
            try self.emitSyntaxError(writer, state_index, &.{}, "    ");
        } else {
            try self.emitActionSwitch(writer, state, entries.items, state_index, 0, "    ");
            try writer.writeByte('\n');
        }

        try writer.writeAll(
            \\    while (true) {
            \\        if (result.is_accept) return result;
            \\        if (result.pops_remaining > 0) {
            \\            result.pops_remaining -= 1;
            \\            return result;
            \\        }
            \\
        );
        if (state.gotos.items.len == 0) {
            try writer.writeAll("        return error.SyntaxError;\n");
        } else {
            try writer.writeAll("        result = switch (result.variable) {\n");
            for (state.gotos.items) |goto| {
                try writer.print("            {d} => try state_{d}(context, stack), // {s}\n", .{ self.variableIndex(goto.variable), goto.state, self.symbols.items[goto.variable].id });
            }
            try writer.writeAll("            else => unreachable,\n        };\n");
        }
        try writer.writeAll("    }\n}\n");
    }

    const SwitchEntry = struct {
        terminal: []const u8,
        action: usize,
    };

    const SwitchGroup = struct {
        heads: std.ArrayList([]const u8) = .empty,
        payload: std.ArrayList(SwitchEntry) = .empty,
    };

    fn emitActionSwitch(self: *Generator, writer: *std.Io.Writer, state: State, entries: []const SwitchEntry, state_index: usize, prefix_length: usize, indent: []const u8) !void {
        const step_length = switchStepLength(entries);
        try writer.print("{s}switch (context.head(u{d}, {d})) {{\n", .{ indent, step_length * 8, prefix_length });
        const groups = try self.buildSwitchGroups(entries, step_length);
        for (groups.items) |group| {
            try writer.print("{s}    ", .{indent});
            for (group.heads.items, 0..) |head, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.print("{d}", .{bytesToInt(head)});
            }
            try writer.writeAll(" => { // ");
            for (group.heads.items, 0..) |head, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.writeByte('\'');
                try emitEscapedForComment(writer, head);
                try writer.writeByte('\'');
            }
            try writer.writeByte('\n');

            if (group.payload.items.len == 1 and group.payload.items[0].terminal.len == 0) {
                try self.emitAction(writer, state.actions.items[group.payload.items[0].action], prefix_length + step_length, try indented(self.allocator, indent, 8));
            } else {
                try self.emitActionSwitch(writer, state, group.payload.items, state_index, prefix_length + step_length, try indented(self.allocator, indent, 8));
                try writer.writeByte('\n');
            }
            try writer.print("{s}    }},\n", .{indent});
        }
        try self.emitSyntaxError(writer, state_index, groups.items, try indented(self.allocator, indent, 4));
        try writer.print("{s}}}", .{indent});
    }

    fn emitAction(self: *Generator, writer: *std.Io.Writer, action: Action, length: usize, indent: []const u8) !void {
        switch (action.kind) {
            .accept => try writer.print(
                \\{s}if (comptime builtin.mode == .Debug) {{
                \\{s}    if (context.verbosityLevel() > 1) {{
                \\{s}        std.debug.print("Accept!\n", .{{}});
                \\{s}    }}
                \\{s}}}
                \\{s}return ReduceResult{{ .variable = 0, .pops_remaining = 0, .is_accept = true }};
                \\
            , .{ indent, indent, indent, indent, indent, indent }),
            .shift => {
                if (self.options.with_ast) {
                    const symbol = self.symbols.items[action.terminal];
                    if (self.options.ast_for_terminals) {
                        try writer.print(
                            \\{s}const node_address = context.node_allocator.create(context.pos(), data_structures.ASTNode.invalid_variable);
                            \\{s}context.node_allocator.at(node_address).text_length = {d};
                            \\{s}try stack.append(context.arena_allocator, node_address);
                            \\
                        , .{ indent, indent, length, indent });
                    } else {
                        try writer.print("{s}try stack.append(context.arena_allocator, context.pos());\n", .{indent});
                    }
                    _ = symbol;
                }
                try writer.print("{s}context.release_token({d});\n", .{ indent, length });
                try writer.print(
                    \\{s}if (comptime builtin.mode == .Debug) {{
                    \\{s}    if (context.verbosityLevel() > 1) {{
                    \\{s}        std.debug.print("Shift: matched '{{s}}', transitioning to state_{d}\n", .{{
                , .{ indent, indent, indent, action.state });
                try emitStringLiteral(writer, self.symbols.items[action.terminal].id);
                try writer.print(
                    \\}});
                    \\{s}    }}
                    \\{s}}}
                    \\{s}result = try state_{d}(context, stack);
                    \\
                , .{ indent, indent, indent, action.state });
            },
            .reduce => try self.emitReduceAction(writer, action.rule, indent),
        }
    }

    fn emitReduceAction(self: *Generator, writer: *std.Io.Writer, rule_index: usize, indent: []const u8) !void {
        const rule = self.rules.items[rule_index];
        const variable_index = self.variableIndex(rule.header);
        const rhs_len = rule.rhs.items.len;

        try writer.print("{s}// Reduce: {s} <- ", .{ indent, self.symbols.items[rule.header].id });
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.writeByte('\n');

        if (self.options.with_ast) {
            var i = rhs_len;
            while (i > 0) {
                i -= 1;
                const sym = rule.rhs.items[i];
                const is_linked = self.symbolReturnsStackNode(sym);
                const needed = (is_linked and self.symbols.items[rule.header].ast_enabled) or i == 0;
                if (needed) {
                    try writer.print("{s}const child_{d} = stack.pop().?;\n", .{ indent, i + 1 });
                } else {
                    try writer.print("{s}_ = stack.pop();\n", .{indent});
                }
            }

            if (rhs_len > 0) {
                const first = rule.rhs.items[0];
                if (self.symbolReturnsStackNode(first)) {
                    try writer.print("{s}const start_pos = context.node_allocator.at(child_1).text_start;\n", .{indent});
                } else {
                    try writer.print("{s}const start_pos = child_1;\n", .{indent});
                }
            } else {
                try writer.print("{s}const start_pos = context.pos();\n", .{indent});
            }

            if (self.symbols.items[rule.header].ast_enabled) {
                try writer.print("{s}const parent_address = context.node_allocator.create(start_pos, {d});\n", .{ indent, variable_index });
                for (rule.rhs.items, 0..) |sym, child_index| {
                    if (self.symbolReturnsStackNode(sym)) {
                        try writer.print("{s}context.node_allocator.at(parent_address).immediate_insert_child(parent_address, child_{d}, context); // child {d}\n", .{ indent, child_index + 1, child_index });
                    }
                }
                if (self.options.with_procedures) {
                    try self.emitProcedureBlock(writer, rule_index, rule.header, "parent_address", indent);
                }
                const stack_value = if (self.options.with_procedures) "args.node orelse data_structures.ASTNode.invalid_pointer" else "parent_address";
                try writer.print("{s}try stack.append(context.arena_allocator, {s});\n", .{ indent, stack_value });
            } else {
                if (self.options.with_procedures) {
                    try self.emitProcedureBlock(writer, rule_index, rule.header, "data_structures.ASTNode.invalid_pointer", indent);
                }
                const stack_value = if (self.options.with_procedures) "args.node orelse start_pos" else "start_pos";
                try writer.print("{s}try stack.append(context.arena_allocator, {s});\n", .{ indent, stack_value });
            }
        }

        try self.emitDebugReduction(writer, rule, indent);
        try writer.print("{s}{s} ReduceResult{{ .variable = {d}, .pops_remaining = {d}, .is_accept = false }};\n", .{
            indent,
            if (rhs_len > 0) "return" else "result =",
            variable_index,
            if (rhs_len > 0) rhs_len - 1 else 0,
        });
    }

    fn emitProcedureBlock(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, node_expr: []const u8, indent: []const u8) !void {
        const variable_index = self.variableIndex(parent_variable);
        try writer.print(
            \\{s}var args = data_structures.ProcedureArguments{{
            \\{s}    .context = context,
            \\{s}    .rule = rules[{d}],
            \\{s}    .node = {s},
            \\{s}}};
            \\{s}if (comptime rule_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\{s}comptime var procedure_pointer_head = variable_procedures[{d}];
            \\{s}inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            \\{s}    try procedure(&args);
            \\{s}    procedure_pointer_head = procedure_pointer_head_.next;
            \\{s}}}
            \\{s}if (comptime symbol_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\{s}if (comptime reduction_procedure) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\
        , .{
            indent, indent,     indent, rule_index, indent, node_expr, indent,
            indent, rule_index, indent, indent,     indent, indent,    variable_index,
            indent, indent,     indent, indent,     indent, indent,    parent_variable,
            indent, indent,     indent, indent,     indent, indent,    indent,
        });
    }

    fn emitDebugReduction(self: *Generator, writer: *std.Io.Writer, rule: Rule, indent: []const u8) !void {
        try writer.print(
            \\{s}if (comptime builtin.mode == .Debug) {{
            \\{s}    if (context.verbosityLevel() > 1) {{
            \\{s}        std.debug.print("Reduction: 
        , .{ indent, indent, indent });
        try emitFormatToken(writer, self.symbols.items[rule.header].id);
        try writer.writeAll(" <~ ");
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.print(
            \\\n", .{{}});
            \\{s}    }}
            \\{s}}}
        , .{ indent, indent });
    }

    fn emitSyntaxError(self: *Generator, writer: *std.Io.Writer, state_index: usize, groups: []const SwitchGroup, indent: []const u8) !void {
        try writer.print(
            \\{s}else => {{
            \\{s}    std.debug.print("\x1b[35mSyntaxError at {{d}}:{{d}}:\n\x1b[37mUnexpected token \x1b[31m\"{{f}}\"\x1b[37m in state {d}.\nExpected tokens: \x1b[32m\'
        , .{ indent, indent, state_index });
        var expected = std.ArrayList([]const u8).empty;
        for (groups) |group| {
            for (group.heads.items) |head| try expected.append(self.allocator, head);
        }
        std.mem.sort([]const u8, expected.items, {}, headLessThan);
        for (expected.items, 0..) |head, i| {
            if (i != 0) try writer.writeAll("', '");
            try emitFormatToken(writer, head);
        }
        try writer.print(
            \\\'\x1b[0m\n", .{{
            \\{s}        if (comptime builtin.mode != .ReleaseFast) context.line else 0,
            \\{s}        if (comptime builtin.mode != .ReleaseFast) context.column else 0,
            \\{s}        string_utilities.fmtString(context.token.items()),
            \\{s}    }});
            \\{s}    return error.SyntaxError;
            \\{s}}},
        , .{ indent, indent, indent, indent, indent, indent });
    }

    fn emitRuleSymbolsForDebug(self: *Generator, writer: *std.Io.Writer, rule: Rule) !void {
        for (rule.rhs.items, 0..) |symbol_index, i| {
            if (i != 0) try writer.writeAll(", ");
            const symbol = self.symbols.items[symbol_index];
            if (symbol.kind == .variable) {
                try emitFormatToken(writer, symbol.id);
            } else {
                try writer.writeByte('\'');
                try emitFormatToken(writer, symbol.id);
                try writer.writeByte('\'');
            }
        }
    }

    fn symbolReturnsStackNode(self: *Generator, symbol_index: usize) bool {
        const symbol = self.symbols.items[symbol_index];
        return (symbol.kind == .variable and symbol.ast_enabled) or (symbol.kind != .variable and self.options.ast_for_terminals);
    }

    fn stateUsesStack(self: *Generator, state: State) bool {
        if (state.gotos.items.len > 0) return true;
        for (state.actions.items) |action| {
            switch (action.kind) {
                .shift => return true,
                .reduce => if (self.options.with_ast) return true,
                .accept => {},
            }
        }
        return false;
    }

    fn variableIndex(self: *Generator, symbol_index: usize) usize {
        for (self.variables.items, 0..) |candidate, index| {
            if (candidate == symbol_index) return index;
        }
        unreachable;
    }

    fn longestTerminalLength(self: *Generator) usize {
        return common.longestTerminalLength(self.symbols.items);
    }

    fn appendSwitchEntry(entries: *std.ArrayList(SwitchEntry), allocator: std.mem.Allocator, terminal: []const u8, action: usize) !void {
        for (entries.items) |entry| {
            if (entry.action == action and std.mem.eql(u8, entry.terminal, terminal)) return;
        }
        try entries.append(allocator, .{ .terminal = terminal, .action = action });
    }

    fn switchEntryLessThan(_: void, lhs: SwitchEntry, rhs: SwitchEntry) bool {
        const order = std.mem.order(u8, lhs.terminal, rhs.terminal);
        if (order != .eq) return order == .lt;
        return lhs.action < rhs.action;
    }

    fn buildSwitchGroups(self: *Generator, entries: []const SwitchEntry, step_length: usize) !std.ArrayList(SwitchGroup) {
        var heads = std.ArrayList([]const u8).empty;
        for (entries) |entry| {
            const head = entry.terminal[0..step_length];
            for (heads.items) |existing| {
                if (std.mem.eql(u8, existing, head)) break;
            } else {
                try heads.append(self.allocator, head);
            }
        }
        std.mem.sort([]const u8, heads.items, {}, headLessThan);

        var groups = std.ArrayList(SwitchGroup).empty;
        for (heads.items) |head| {
            var payload = std.ArrayList(SwitchEntry).empty;
            for (entries) |entry| {
                if (!std.mem.eql(u8, entry.terminal[0..step_length], head)) continue;
                try appendSwitchEntry(&payload, self.allocator, entry.terminal[step_length..], entry.action);
            }
            std.mem.sort(SwitchEntry, payload.items, {}, switchEntryLessThan);

            var found: ?usize = null;
            for (groups.items, 0..) |group, i| {
                if (switchPayloadEqual(group.payload.items, payload.items)) {
                    found = i;
                    break;
                }
            }
            if (found) |index| {
                try groups.items[index].heads.append(self.allocator, head);
            } else {
                var group = SwitchGroup{ .payload = payload };
                try group.heads.append(self.allocator, head);
                try groups.append(self.allocator, group);
            }
        }

        for (groups.items) |*group| {
            std.mem.sort([]const u8, group.heads.items, {}, headLessThan);
        }
        std.mem.sort(SwitchGroup, groups.items, {}, switchGroupLessThan);
        return groups;
    }
};

pub fn emitParser(allocator: std.mem.Allocator, grammar: anytype, writer: *std.Io.Writer) !void {
    try emitParserWithOptions(allocator, grammar, writer, .{});
}

pub fn emitParserWithOptions(allocator: std.mem.Allocator, grammar: anytype, writer: *std.Io.Writer, options: Options) !void {
    var generator = Generator.init(allocator, options);
    try generator.fromGrammar(grammar);
    try generator.emit(writer);
}

fn appendItemUnique(items: *std.ArrayList(Item), allocator: std.mem.Allocator, item: Item) !void {
    for (items.items) |existing| {
        if (itemEqual(existing, item)) return;
    }
    try items.append(allocator, item);
}

fn itemEqual(lhs: Item, rhs: Item) bool {
    return lhs.variable == rhs.variable and lhs.rule == rhs.rule and lhs.head == rhs.head and lhs.lookahead == rhs.lookahead;
}

fn itemLessThan(_: void, lhs: Item, rhs: Item) bool {
    if (lhs.variable != rhs.variable) return lhs.variable < rhs.variable;
    if (lhs.rule != rhs.rule) return lhs.rule < rhs.rule;
    if (lhs.head != rhs.head) return lhs.head < rhs.head;
    return lhs.lookahead < rhs.lookahead;
}

fn itemsEqual(lhs: []const Item, rhs: []const Item) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |a, b| {
        if (!itemEqual(a, b)) return false;
    }
    return true;
}

fn switchStepLength(entries: []const Generator.SwitchEntry) usize {
    var step_length: usize = std.math.maxInt(usize);
    for (entries) |entry| {
        if (entry.terminal.len > 0) step_length = @min(step_length, entry.terminal.len);
    }
    return step_length;
}

fn headLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn switchGroupLessThan(_: void, lhs: Generator.SwitchGroup, rhs: Generator.SwitchGroup) bool {
    return std.mem.order(u8, lhs.heads.items[0], rhs.heads.items[0]) == .lt;
}

fn switchPayloadEqual(lhs: []const Generator.SwitchEntry, rhs: []const Generator.SwitchEntry) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |a, b| {
        if (a.action != b.action or !std.mem.eql(u8, a.terminal, b.terminal)) return false;
    }
    return true;
}
