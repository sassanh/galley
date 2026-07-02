const std = @import("std");

pub const Options = struct {
    with_ast: bool = true,
    with_procedures: bool = true,
    ast_for_terminals: bool = false,
    input_size: u16 = 16,
};

const SymbolKind = enum { variable, terminal, generative_terminal, end };

const Symbol = struct {
    id: []const u8,
    kind: SymbolKind,
    ast_enabled: bool = true,
    terminals: std.ArrayList([]const u8) = .empty,
    procedures: std.ArrayList([]const u8) = .empty,
};

const Rule = struct {
    header: usize,
    rhs: std.ArrayList(usize) = .empty,
    rhs_index: []const u8,
};

const Generator = struct {
    allocator: std.mem.Allocator,
    options: Options,
    symbols: std.ArrayList(Symbol) = .empty,
    variables: std.ArrayList(usize) = .empty,
    rules: std.ArrayList(Rule) = .empty,
    parse_table: std.ArrayList(ParseEntry) = .empty,
    needs_non_ast_parser: std.AutoHashMap(usize, void) = undefined,
    augmented_start: usize = 0,

    const ParseEntry = struct {
        variable: usize,
        terminal: usize,
        rule: usize,
    };

    fn init(allocator: std.mem.Allocator, options: Options) Generator {
        return .{
            .allocator = allocator,
            .options = options,
            .needs_non_ast_parser = std.AutoHashMap(usize, void).init(allocator),
        };
    }

    fn addSymbol(self: *Generator, id: []const u8, kind: SymbolKind, procedures_: []const []const u8) !usize {
        for (self.symbols.items, 0..) |symbol, index| {
            if (std.mem.eql(u8, symbol.id, id)) return index;
        }

        var symbol = Symbol{
            .id = try self.allocator.dupe(u8, id),
            .kind = kind,
            .ast_enabled = !(kind == .variable and id.len > 0 and id[0] == '_'),
        };
        for (procedures_) |procedure| try symbol.procedures.append(self.allocator, try self.allocator.dupe(u8, procedure));
        if (kind == .terminal or kind == .end) {
            try symbol.terminals.append(self.allocator, symbol.id);
        } else if (kind == .generative_terminal) {
            try expandGenerativeTerminal(self.allocator, &symbol.terminals, id);
        }

        const index = self.symbols.items.len;
        try self.symbols.append(self.allocator, symbol);
        if (kind == .variable) try self.variables.append(self.allocator, index);
        return index;
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
        const augmented_start = try self.addSymbol("_AugmentedStart", .variable, &.{});
        self.augmented_start = augmented_start;
        const eof = try self.addSymbol("\x00", .end, &.{});
        var augmented_rule = Rule{ .header = augmented_start, .rhs_index = "0" };
        try augmented_rule.rhs.append(self.allocator, original_start);
        try augmented_rule.rhs.append(self.allocator, eof);
        try self.rules.append(self.allocator, augmented_rule);

        const generative_terminal = try self.addSymbol("GenerativeTerminal", .variable, &.{});
        try self.rules.append(self.allocator, .{ .header = generative_terminal, .rhs_index = "0" });

        std.mem.sort(Rule, self.rules.items, self, ruleLessThan);
        try self.buildParseTable();
    }

    fn ruleLessThan(self: *Generator, lhs: Rule, rhs: Rule) bool {
        const lhs_header = self.symbols.items[lhs.header].id;
        const rhs_header = self.symbols.items[rhs.header].id;
        const header_order = std.mem.order(u8, lhs_header, rhs_header);
        if (header_order != .eq) return header_order == .lt;

        const min_len = @min(lhs.rhs.items.len, rhs.rhs.items.len);
        var i: usize = 0;
        while (i < min_len) : (i += 1) {
            if (lhs.rhs.items[i] != rhs.rhs.items[i]) return lhs.rhs.items[i] < rhs.rhs.items[i];
        }
        return lhs.rhs.items.len < rhs.rhs.items.len;
    }

    fn buildParseTable(self: *Generator) !void {
        for (self.variables.items) |variable| {
            var first_set = std.AutoHashMap(usize, usize).init(self.allocator);
            defer first_set.deinit();
            try self.firsts(variable, &first_set, null);

            const nullable_rule = self.nullableRule(variable);
            var iterator = first_set.iterator();
            while (iterator.next()) |entry| {
                    try self.addParseEntry(.{
                        .variable = variable,
                        .terminal = entry.key_ptr.*,
                        .rule = entry.value_ptr.*,
                    });
            }

            if (nullable_rule) |rule_index| {
                var follow_set = std.AutoHashMap(usize, usize).init(self.allocator);
                defer follow_set.deinit();
                try self.follows(variable, &follow_set, null);
                var follow_iterator = follow_set.iterator();
                while (follow_iterator.next()) |entry| {
                    try self.addParseEntry(.{
                        .variable = variable,
                        .terminal = entry.key_ptr.*,
                        .rule = rule_index,
                    });
                }
            }
        }
    }

    fn nullableRule(self: *Generator, variable: usize) ?usize {
        for (self.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items) |symbol_index| {
                if (self.symbols.items[symbol_index].kind != .variable or self.nullableRule(symbol_index) == null) break;
            } else {
                return rule_index;
            }
        }
        return null;
    }

    fn firsts(self: *Generator, variable: usize, out: *std.AutoHashMap(usize, usize), visited: ?*std.AutoHashMap(usize, void)) !void {
        if (visited) |set| {
            if (set.contains(variable)) return;
        }
        var local_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer local_visited.deinit();
        if (visited) |set| {
            var it = set.iterator();
            while (it.next()) |entry| try local_visited.put(entry.key_ptr.*, {});
        }
        try local_visited.put(variable, {});

        for (self.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items) |symbol_index| {
                const symbol = self.symbols.items[symbol_index];
                if (symbol.kind == .variable) {
                    var child_firsts = std.AutoHashMap(usize, usize).init(self.allocator);
                    defer child_firsts.deinit();
                    try self.firsts(symbol_index, &child_firsts, &local_visited);
                    var child_iterator = child_firsts.iterator();
                    while (child_iterator.next()) |entry| {
                        try putUnique(out, entry.key_ptr.*, rule_index);
                    }
                } else {
                    try putUnique(out, symbol_index, rule_index);
                }
                if (symbol.kind != .variable or self.nullableRule(symbol_index) == null) break;
            }
        }
    }

    fn follows(self: *Generator, variable: usize, out: *std.AutoHashMap(usize, usize), visited: ?*std.AutoHashMap(usize, void)) !void {
        if (visited) |set| {
            if (set.contains(variable)) return;
        }
        var local_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer local_visited.deinit();
        if (visited) |set| {
            var it = set.iterator();
            while (it.next()) |entry| try local_visited.put(entry.key_ptr.*, {});
        }
        try local_visited.put(variable, {});

        for (self.rules.items, 0..) |rule, rule_index| {
            for (rule.rhs.items, 0..) |symbol_index, rhs_pos| {
                if (symbol_index != variable) continue;
                var propagated = true;
                var next_pos = rhs_pos + 1;
                while (next_pos < rule.rhs.items.len) : (next_pos += 1) {
                    const next_symbol_index = rule.rhs.items[next_pos];
                    const next_symbol = self.symbols.items[next_symbol_index];
                    if (next_symbol.kind == .variable) {
                        var next_firsts = std.AutoHashMap(usize, usize).init(self.allocator);
                        defer next_firsts.deinit();
                        try self.firsts(next_symbol_index, &next_firsts, null);
                        var it = next_firsts.iterator();
                        while (it.next()) |entry| try out.put(entry.key_ptr.*, entry.value_ptr.*);
                    } else {
                        try out.put(next_symbol_index, rule_index);
                    }
                    if (next_symbol.kind != .variable or self.nullableRule(next_symbol_index) == null) {
                        propagated = false;
                        break;
                    }
                }
                if (propagated and rule.header != variable) {
                    try self.follows(rule.header, out, &local_visited);
                }
            }
        }
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
        if (self.options.with_procedures and self.options.with_ast) try self.emitProcedureBoilerplate(writer);
        try self.emitParserFunctions(writer);
        try self.emitNonAstParsers(writer);
        try writer.writeAll(
            \\pub fn parse(context: *data_structures.Context) !void {
            \\    _ = parse__AugmentedStart(context) catch {
            \\        if (comptime builtin.mode == .Debug) {
            \\            return error.ParseError;
            \\        }
            \\        return;
            \\    };
            \\
            \\    if (context.verbosity > 0) {
            \\        std.log.info("The input file was parsed successfully!", .{});
            \\    }
            \\}
            \\
        );
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

    fn emitParserFunctions(self: *Generator, writer: *std.Io.Writer) !void {
        for (self.symbols.items, 0..) |symbol, symbol_index| {
            if (symbol.kind == .variable) {
                if (!self.hasParseEntries(symbol_index)) continue;
                try self.emitVariableParser(writer, symbol_index, false);
            } else {
                try self.emitTerminalParser(writer, symbol_index, false);
            }
            try writer.writeByte('\n');
        }
    }

    fn emitNonAstParsers(self: *Generator, writer: *std.Io.Writer) !void {
        var generated = std.AutoHashMap(usize, void).init(self.allocator);
        while (generated.count() < self.needs_non_ast_parser.count()) {
            for (0..self.symbols.items.len) |symbol_index| {
                if (!self.needs_non_ast_parser.contains(symbol_index)) continue;
                if (generated.contains(symbol_index)) continue;
                try generated.put(symbol_index, {});

                try writer.writeByte('\n');
                const symbol = self.symbols.items[symbol_index];
                if (symbol.kind == .variable) {
                    if (!self.hasParseEntries(symbol_index)) continue;
                    try self.emitVariableParser(writer, symbol_index, true);
                } else {
                    try self.emitTerminalParser(writer, symbol_index, true);
                }
            }
        }
        if (generated.count() > 0) try writer.writeByte('\n');
    }

    fn markNeedsNonAst(self: *Generator, symbol_index: usize) !void {
        if (self.needs_non_ast_parser.contains(symbol_index)) return;
        try self.needs_non_ast_parser.put(symbol_index, {});
    }

    fn parserName(self: *Generator, symbol_index: usize) ![]const u8 {
        const symbol = self.symbols.items[symbol_index];
        if (symbol.kind == .end) return self.allocator.dupe(u8, "special_EOF");
        const prefix = switch (symbol.kind) {
            .variable => "",
            .terminal => "terminal_",
            .generative_terminal => "generative_terminal_",
            .end => unreachable,
        };
        const repr = try readableSymbolName(self.allocator, symbol.id);
        const text = try std.mem.concat(self.allocator, u8, &.{ prefix, repr });
        return safeIdentifier(self.allocator, text);
    }

    fn emitVariableParser(self: *Generator, writer: *std.Io.Writer, variable: usize, non_ast: bool) !void {
        try self.emitSelfRepeatingParsers(writer, variable, non_ast);
        const name = try self.parserName(variable);
        const returns_node = self.symbolReturnsNode(variable, non_ast);
        try writer.print("// {s}Parser for Symbol \"", .{if (non_ast) "Non-AST " else ""});
        try std.zig.stringEscape(self.symbols.items[variable].id, writer);
        try writer.print("\" with index {d}\n", .{variable});
        try writer.print("fn parse_{s}{s}(context: *data_structures.Context) anyerror!{s} {{\n", .{ name, if (non_ast) "_" else "", if (returns_node) "data_structures.ASTNode.Pointer" else "void" });
        if (returns_node) {
            const variable_index = self.variableIndex(variable);
            try writer.print("    const node_address = context.node_allocator.create(context.pos(), {d});\n\n", .{variable_index});
        }

        var entries = std.ArrayList(SwitchEntry).empty;

        for (self.parse_table.items) |entry| {
            if (entry.variable != variable) continue;
            const terminal = self.symbols.items[entry.terminal];
            for (terminal.terminals.items) |terminal_item| {
                try appendSwitchEntry(&entries, self.allocator, terminal_item, entry.rule);
            }
        }

        if (entries.items.len == 0) {
            try writer.writeAll("    switch (context.head(u8, 0)) {\n        else => return error.SyntaxError,\n    }\n");
        } else {
            try self.emitRuleSwitch(writer, variable, entries.items, 0, "    ", non_ast, false);
            try writer.writeByte('\n');
        }
        if (returns_node) {
            try writer.writeAll("    return node_address;\n");
        }
        try writer.writeAll("}\n");
    }

    fn emitSelfRepeatingParsers(self: *Generator, writer: *std.Io.Writer, variable: usize, non_ast: bool) !void {
        for (self.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items, 0..) |symbol_index, child_index| {
                if (symbol_index != variable) continue;
                try self.emitSelfRepeatingParser(writer, variable, rule_index, child_index, non_ast);
                try writer.writeByte('\n');
            }
        }
    }

    fn symbolReturnsNode(self: *Generator, symbol_index: usize, non_ast: bool) bool {
        const symbol = self.symbols.items[symbol_index];
        return self.options.with_ast and !non_ast and ((symbol.kind == .variable and symbol.ast_enabled) or (symbol.kind != .variable and self.options.ast_for_terminals));
    }

    fn hasParseEntries(self: *Generator, variable: usize) bool {
        for (self.parse_table.items) |entry| {
            if (entry.variable == variable) return true;
        }
        return false;
    }

    fn emitSelfRepeatingParser(self: *Generator, writer: *std.Io.Writer, variable: usize, rule_index: usize, self_index: usize, non_ast: bool) !void {
        const rule = self.rules.items[rule_index];
        const name = try self.parserName(variable);
        const returns_node = self.symbolReturnsNode(variable, non_ast);
        try writer.print("// {s}Self-Repeating Parser for Symbol \"", .{if (non_ast) "Non-AST " else ""});
        try self.emitSymbolRepr(writer, variable);
        try writer.print("\" at index {d} of its right hand side\n// Right hand side: -> ", .{self_index});
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.print("\nfn parse_{s}_{s}_{d}{s}(context: *data_structures.Context) anyerror!{s} {{\n", .{
            name,
            rule.rhs_index,
            self_index,
            if (non_ast) "_" else "",
            if (returns_node) "data_structures.ASTNode.Pointer" else "void",
        });

        if (returns_node) {
            try writer.writeAll(
                \\    var node_address = data_structures.ASTNode.invalid_pointer;
                \\    var repeating_node_address = node_address;
                \\    var repeating_node: *data_structures.ASTNode = undefined;
                \\
            );
        }

        var cases = std.ArrayList(u8).empty;
        for (self.parse_table.items) |entry| {
            if (entry.variable != variable or entry.rule != rule_index) continue;
            for (self.symbols.items[entry.terminal].terminals.items) |terminal| {
                if (terminal.len > 0 and !byteListContains(cases.items, terminal[0])) try cases.append(self.allocator, terminal[0]);
            }
        }
        std.mem.sort(u8, cases.items, {}, comptime std.sort.asc(u8));

        try writer.writeAll("\n    while (true) {\n        switch (context.head(u8, 0)) {\n            ");
        for (cases.items, 0..) |byte, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.print("{d}", .{byte});
        }
        try writer.writeAll(" => { // ");
        for (cases.items, 0..) |byte, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.writeByte('\'');
            try emitEscapedForComment(writer, &.{byte});
            try writer.writeByte('\'');
        }
        try writer.writeByte('\n');
        try self.emitDebugRuleExpansion(writer, rule, variable, "                ");

        if (returns_node) {
            try writer.print(
                \\                const temporary_address = context.node_allocator.create(context.pos(), {d});
                \\                if (node_address == data_structures.ASTNode.invalid_pointer) {{
                \\                    node_address = temporary_address;
                \\                }} else {{
                \\                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child {d}
                \\                }}
                \\                repeating_node_address = temporary_address;
                \\                repeating_node = context.node_allocator.at(repeating_node_address);
                \\
            , .{ self.variableIndex(variable), self_index });
        }

        const prefix_non_ast = self.options.with_ast and (non_ast or !self.symbols.items[variable].ast_enabled);
        for (rule.rhs.items[0..self_index], 0..) |symbol_index, child_index| {
            try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, if (returns_node) "repeating_node" else null, if (returns_node) "repeating_node_address" else null, "                ", prefix_non_ast);
        }
        try writer.writeAll("            },\n            else => break,\n        }\n    }\n");

        if (returns_node) {
            try writer.print(
                \\    const exit_node = try parse_{s}(context);
                \\    if (node_address == data_structures.ASTNode.invalid_pointer) {{
                \\        node_address = exit_node;
                \\    }} else {{
                \\        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child {d}
                \\    }}
                \\    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {{
                \\        repeating_node = context.node_allocator.at(repeating_node_address);
            , .{ name, self_index });
            try writer.writeByte('\n');
            try writer.writeByte('\n');
            try self.emitDebugReduction(writer, rule, variable, "        ");
            if (self.options.with_procedures and self.options.with_ast) {
                try writer.writeByte('\n');
                try self.emitProcedureBlock(writer, rule_index, variable, "repeating_node_address", "        ", true);
                try writer.writeByte('\n');
            }
            try writer.writeAll(
                \\        repeating_node_address = repeating_node.parent;
                \\    }
                \\    return node_address;
                \\
            );
        } else {
            try writer.print("    try parse_{s}{s}(context);\n", .{ name, if (self.options.with_ast) "_" else "" });
        }

        try writer.writeAll("}\n");
    }

    fn emitTerminalParser(self: *Generator, writer: *std.Io.Writer, terminal_index: usize, non_ast: bool) !void {
        const symbol = self.symbols.items[terminal_index];
        const name = try self.parserName(terminal_index);
        const returns_node = self.symbolReturnsNode(terminal_index, non_ast);
        try writer.print("// {s}Parser for Symbol \"", .{if (non_ast) "Non-AST " else ""});
        try self.emitSymbolRepr(writer, terminal_index);
        try writer.print("\" with index {d}\n", .{terminal_index});
        try writer.print("inline fn parse_{s}{s}(context: *data_structures.Context) anyerror!{s} {{\n", .{ name, if (non_ast) "_" else "", if (returns_node) "data_structures.ASTNode.Pointer" else "void" });
        if (returns_node) {
            try writer.writeAll("    const node_address = context.node_allocator.create(context.pos(), data_structures.ASTNode.invalid_variable);\n\n");
        }

        var entries = std.ArrayList(SwitchEntry).empty;
        for (symbol.terminals.items) |terminal| {
            try appendSwitchEntry(&entries, self.allocator, terminal, 0);
        }
        try self.emitRuleSwitch(writer, terminal_index, entries.items, 0, "    ", non_ast, false);
        try writer.writeByte('\n');
        if (returns_node) {
            try writer.writeAll("    return node_address;\n");
        }

        try writer.writeAll("}\n");
    }

    const SwitchEntry = struct {
        terminal: []const u8,
        rule: usize,
    };

    const SwitchGroup = struct {
        heads: std.ArrayList([]const u8) = .empty,
        payload: std.ArrayList(SwitchEntry) = .empty,
    };

    fn appendSwitchEntry(entries: *std.ArrayList(SwitchEntry), allocator: std.mem.Allocator, terminal: []const u8, rule: usize) !void {
        for (entries.items) |entry| {
            if (entry.rule == rule and std.mem.eql(u8, entry.terminal, terminal)) return;
        }
        try entries.append(allocator, .{ .terminal = terminal, .rule = rule });
    }

    fn switchEntryLessThan(_: void, lhs: SwitchEntry, rhs: SwitchEntry) bool {
        const order = std.mem.order(u8, lhs.terminal, rhs.terminal);
        if (order != .eq) return order == .lt;
        return lhs.rule < rhs.rule;
    }

    fn headLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
        return std.mem.order(u8, lhs, rhs) == .lt;
    }

    fn byteListContains(items: []const u8, byte: u8) bool {
        for (items) |item| if (item == byte) return true;
        return false;
    }

    fn switchGroupLessThan(_: void, lhs: SwitchGroup, rhs: SwitchGroup) bool {
        return std.mem.order(u8, lhs.heads.items[0], rhs.heads.items[0]) == .lt;
    }

    fn switchPayloadEqual(lhs: []const SwitchEntry, rhs: []const SwitchEntry) bool {
        if (lhs.len != rhs.len) return false;
        for (lhs, rhs) |a, b| {
            if (a.rule != b.rule or !std.mem.eql(u8, a.terminal, b.terminal)) return false;
        }
        return true;
    }

    fn switchStepLength(entries: []const SwitchEntry) usize {
        var step_length: usize = std.math.maxInt(usize);
        for (entries) |entry| {
            if (entry.terminal.len > 0) step_length = @min(step_length, entry.terminal.len);
        }
        return step_length;
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
                try appendSwitchEntry(&payload, self.allocator, entry.terminal[step_length..], entry.rule);
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

    fn emitRuleSwitch(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, entries: []const SwitchEntry, prefix_length: usize, indent: []const u8, non_ast: bool, is_self_repeating: bool) !void {
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
                try self.emitSwitchLeaf(writer, symbol_index, group.payload.items[0].rule, prefix_length + step_length, indent, non_ast);
            } else {
                var child_indent = std.ArrayList(u8).empty;
                try child_indent.appendSlice(self.allocator, indent);
                try child_indent.appendSlice(self.allocator, "        ");
                try self.emitRuleSwitch(writer, symbol_index, group.payload.items, prefix_length + step_length, child_indent.items, non_ast, is_self_repeating);
                try writer.writeByte('\n');
            }
            try writer.print("{s}    }},\n", .{indent});
        }
        try self.emitSwitchElse(writer, symbol_index, groups.items, indent, is_self_repeating);
        try writer.print("{s}}}", .{indent});
    }

    fn emitSwitchLeaf(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, rule_index: usize, length: usize, indent: []const u8, non_ast: bool) !void {
        const symbol = self.symbols.items[symbol_index];
        if (symbol.kind == .variable) {
            try self.emitRuleBody(writer, rule_index, symbol_index, try indented(self.allocator, indent, 8), non_ast);
        } else {
            try writer.print("{s}        context.release_token({d});\n", .{ indent, length });
        }
    }

    fn emitSwitchElse(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, groups: []const SwitchGroup, indent: []const u8, is_self_repeating: bool) !void {
        if (is_self_repeating) {
            try writer.print("{s}    else => break,\n", .{indent});
            return;
        }
        try writer.print(
            \\{s}    else => {{
            \\{s}        std.debug.print("\x1b[35mSyntaxError at {{d}}:{{d}}:\n\x1b[37mUnexpected token \x1b[31m\"{{f}}\"\x1b[37m while parsing \x1b[34m
        , .{ indent, indent });
        try emitFormatToken(writer, self.symbols.items[symbol_index].id);
        try writer.writeAll("\\x1b[0m.\\nExpected tokens: \\x1b[32m\\'");
        var first = true;
        var expected_heads = std.ArrayList([]const u8).empty;
        for (groups) |group| {
            for (group.heads.items) |head| try expected_heads.append(self.allocator, head);
        }
        std.mem.sort([]const u8, expected_heads.items, {}, headLessThan);
        for (expected_heads.items) |head| {
            if (!first) try writer.writeAll("', '");
            first = false;
            try emitFormatToken(writer, head);
        }
        try writer.print(
            \\\'\x1b[0m\n", .{{
            \\{s}            if (comptime builtin.mode != .ReleaseFast) context.line else 0,
            \\{s}            if (comptime builtin.mode != .ReleaseFast) context.column else 0,
            \\{s}            string_utilities.fmtString(context.token.items()),
            \\{s}        }});
            \\{s}        return error.SyntaxError;
            \\{s}    }},
            \\
        , .{ indent, indent, indent, indent, indent, indent });
    }

    fn emitRuleBody(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, indent: []const u8, non_ast: bool) !void {
        const rule = self.rules.items[rule_index];
        const parent_returns_node = self.symbolReturnsNode(parent_variable, non_ast);
        if (rule.rhs.items.len == 0) return;

        try self.emitDebugRuleExpansion(writer, rule, parent_variable, indent);

        for (rule.rhs.items, 0..) |symbol_index, child_index| {
            const name = try self.parserName(symbol_index);
            const child = self.symbols.items[symbol_index];
            const child_non_ast = self.options.with_ast and (non_ast or (child.kind == .variable and !child.ast_enabled));
            if (child_non_ast) try self.markNeedsNonAst(symbol_index);
            const child_returns_node = self.symbolReturnsNode(symbol_index, child_non_ast);
            const call_name = if (symbol_index == parent_variable)
                try std.fmt.allocPrint(self.allocator, "{s}_{s}_{d}", .{ name, rule.rhs_index, child_index })
            else
                name;
            if (parent_returns_node and child_returns_node) {
                try writer.print("{s}context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_{s}(context), context); // child {d}\n", .{ indent, call_name, child_index });
            } else if (child_returns_node) {
                try writer.print("{s}_ = try parse_{s}(context); // child {d}\n", .{ indent, call_name, child_index });
            } else {
                try writer.print("{s}try parse_{s}{s}(context); // child {d}\n", .{ indent, call_name, if (child_non_ast) "_" else "", child_index });
            }
        }

        if (self.options.with_procedures and self.options.with_ast and !non_ast) {
            const variable_index = self.variableIndex(parent_variable);
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = rules[{d}],
                \\{s}    .node = {s},
                \\{s}}};
                \\
                \\{s}if (comptime rule_procedures[{d}]) |procedure_pointer| {{
                \\{s}    const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                \\{s}    try procedure(&args);
                \\{s}}}
                \\
                \\{s}comptime var procedure_pointer_head = variable_procedures[{d}];
                \\{s}inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {{
                \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                \\{s}    try procedure(&args);
                \\{s}    procedure_pointer_head = procedure_pointer_head_.next;
                \\{s}}}
                \\
                \\{s}if (comptime symbol_procedures[{d}]) |procedure_pointer| {{
                \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                \\{s}    try procedure(&args);
                \\{s}}}
                \\
                \\{s}if (comptime reduction_procedure) |procedure_pointer| {{
                \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                \\{s}    try procedure(&args);
                \\{s}}}
                \\
            , .{
                indent, indent, indent, rule_index, indent, if (parent_returns_node) "node_address" else "null", indent,
                indent, rule_index, indent, indent, indent,
                indent, variable_index, indent, indent, indent, indent, indent,
                indent, parent_variable, indent, indent, indent,
                indent, indent, indent, indent,
            });
            if (parent_returns_node) {
                try writer.writeByte('\n');
                try writer.print(
                    \\{s}if (comptime builtin.mode == .Debug) {{
                    \\{s}    if (context.verbosity > 2) {{
                    \\{s}        std.debug.print("Procedure outcome for 
                , .{ indent, indent, indent });
                try emitFormatToken(writer, self.symbols.items[parent_variable].id);
                try writer.print(
                    \\: {{f}}\n", .{{
                    \\{s}            string_utilities.fmtASTNode(args.node, context),
                    \\{s}        }});
                    \\{s}    }}
                    \\{s}}}
                    \\
                , .{ indent, indent, indent, indent });
            }
        }

        if (self.options.with_procedures and self.options.with_ast and !non_ast) try writer.writeByte('\n');
        try self.emitDebugReduction(writer, rule, parent_variable, indent);
    }

    fn emitChildParseLine(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, parent_variable: usize, rule: Rule, child_index: usize, parent: ?[]const u8, parent_address: ?[]const u8, indent: []const u8, non_ast: bool) !void {
        const name = try self.parserName(symbol_index);
        const child = self.symbols.items[symbol_index];
        const child_non_ast = self.options.with_ast and (non_ast or (child.kind == .variable and !child.ast_enabled));
        if (child_non_ast) try self.markNeedsNonAst(symbol_index);
        const child_returns_node = self.symbolReturnsNode(symbol_index, child_non_ast);
        const call_name = if (symbol_index == parent_variable)
            try std.fmt.allocPrint(self.allocator, "{s}_{s}_{d}", .{ name, rule.rhs_index, child_index })
        else
            name;
        if (parent) |parent_expr| {
            if (child_returns_node) {
                try writer.print("{s}{s}.immediate_insert_child({s}, try parse_{s}(context), context); // child {d}\n", .{ indent, parent_expr, parent_address.?, call_name, child_index });
            } else {
                try writer.print("{s}try parse_{s}{s}(context); // child {d}\n", .{ indent, call_name, if (child_non_ast) "_" else "", child_index });
            }
        } else if (child_returns_node) {
            try writer.print("{s}_ = try parse_{s}(context); // child {d}\n", .{ indent, call_name, child_index });
        } else {
            try writer.print("{s}try parse_{s}{s}(context); // child {d}\n", .{ indent, call_name, if (child_non_ast) "_" else "", child_index });
        }
    }

    fn emitProcedureBlock(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, node_expr: []const u8, indent: []const u8, include_outcome: bool) !void {
        const variable_index = self.variableIndex(parent_variable);
        try writer.print(
            \\{s}var args = data_structures.ProcedureArguments{{
            \\{s}    .context = context,
            \\{s}    .rule = rules[{d}],
            \\{s}    .node = {s},
            \\{s}}};
            \\
            \\{s}if (comptime rule_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\
            \\{s}comptime var procedure_pointer_head = variable_procedures[{d}];
            \\{s}inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            \\{s}    try procedure(&args);
            \\{s}    procedure_pointer_head = procedure_pointer_head_.next;
            \\{s}}}
            \\
            \\{s}if (comptime symbol_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\
            \\{s}if (comptime reduction_procedure) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\
        , .{
            indent, indent, indent, rule_index, indent, node_expr, indent,
            indent, rule_index, indent, indent, indent,
            indent, variable_index, indent, indent, indent, indent, indent,
            indent, parent_variable, indent, indent, indent,
            indent, indent, indent, indent,
        });
        if (include_outcome) {
            try writer.print(
                \\
                \\{s}if (comptime builtin.mode == .Debug) {{
                \\{s}    if (context.verbosity > 2) {{
                \\{s}        std.debug.print("Procedure outcome for 
            , .{ indent, indent, indent });
            try emitFormatToken(writer, self.symbols.items[parent_variable].id);
            try writer.print(
                \\: {{f}}\n", .{{
                \\{s}            string_utilities.fmtASTNode(args.node, context),
                \\{s}        }});
                \\{s}    }}
                \\{s}}}
                \\
            , .{ indent, indent, indent, indent });
        }
    }

    fn emitDebugRuleExpansion(self: *Generator, writer: *std.Io.Writer, rule: Rule, parent_variable: usize, indent: []const u8) !void {
        try writer.print(
            \\{s}if (comptime builtin.mode == .Debug) {{
            \\{s}    if (context.verbosity > 1) {{
            \\{s}        std.debug.print("Rule expansion: 
        , .{ indent, indent, indent });
        try emitFormatToken(writer, self.symbols.items[parent_variable].id);
        try writer.writeAll(" -> ");
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.print(
            \\\n", .{{}});
            \\{s}    }}
            \\{s}}}
            \\
        , .{ indent, indent });
    }

    fn emitDebugReduction(self: *Generator, writer: *std.Io.Writer, rule: Rule, parent_variable: usize, indent: []const u8) !void {
        try writer.print(
            \\{s}if (comptime builtin.mode == .Debug) {{
            \\{s}    if (context.verbosity > 1) {{
            \\{s}        std.debug.print("Reduction: 
        , .{ indent, indent, indent });
        try emitFormatToken(writer, self.symbols.items[parent_variable].id);
        try writer.writeAll(" <~ ");
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.print(
            \\\n", .{{}});
            \\{s}    }}
            \\{s}}}
            \\
        , .{ indent, indent });
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

    fn emitSymbolRepr(self: *Generator, writer: *std.Io.Writer, symbol_index: usize) !void {
        const symbol = self.symbols.items[symbol_index];
        if (symbol.kind == .end) {
            try writer.writeAll("special_EOF");
            return;
        }
        switch (symbol.kind) {
            .variable => {},
            .terminal => try writer.writeAll("terminal_"),
            .generative_terminal => try writer.writeAll("generative_terminal_"),
            .end => unreachable,
        }
        const repr = try readableSymbolName(self.allocator, symbol.id);
        try writer.writeAll(repr);
    }

    fn variableIndex(self: *Generator, symbol_index: usize) usize {
        for (self.variables.items, 0..) |candidate, index| {
            if (candidate == symbol_index) return index;
        }
        unreachable;
    }

    fn addParseEntry(self: *Generator, entry: ParseEntry) !void {
        for (self.parse_table.items) |existing| {
            if (existing.variable == entry.variable and existing.terminal == entry.terminal) {
                if (existing.rule != entry.rule) return error.AmbiguousGrammar;
                return;
            }
        }
        try self.parse_table.append(self.allocator, entry);
    }

    fn longestTerminalLength(self: *Generator) usize {
        var longest: usize = 0;
        for (self.symbols.items) |symbol| {
            for (symbol.terminals.items) |terminal| longest = @max(longest, terminal.len);
        }
        return longest;
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

fn putUnique(map: *std.AutoHashMap(usize, usize), key: usize, value: usize) !void {
    if (map.get(key)) |existing| {
        if (existing != value) return error.AmbiguousGrammar;
        return;
    }
    try map.put(key, value);
}

fn emitStringLiteral(writer: *std.Io.Writer, bytes: []const u8) !void {
    try writer.writeByte('"');
    try std.zig.stringEscape(bytes, writer);
    try writer.writeByte('"');
}

fn emitEscapedForComment(writer: *std.Io.Writer, bytes: []const u8) !void {
    try std.zig.stringEscape(bytes, writer);
}

fn emitFormatToken(writer: *std.Io.Writer, bytes: []const u8) !void {
    for (bytes) |byte| {
        switch (byte) {
            '\n' => try writer.writeAll("\\\\n"),
            '\t' => try writer.writeAll("\\\\t"),
            '\r' => try writer.writeAll("\\\\r"),
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\\\\\"),
            '{' => try writer.writeAll("{{"),
            '}' => try writer.writeAll("}}"),
            0 => try writer.writeAll("\\\\x00"),
            0x01...0x08, 0x0b, 0x0c, 0x0e...0x1f, 0x7f...0xff => try writer.print("\\\\x{x:0>2}", .{byte}),
            else => try writer.writeByte(byte),
        }
    }
}

fn readableSymbolName(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    for (bytes) |byte| {
        switch (byte) {
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            0x0b => try out.appendSlice(allocator, "\\x0b"),
            0x0c => try out.appendSlice(allocator, "\\x0c"),
            0x00...0x08, 0x0e...0x1f, 0x7f...0xff => {
                const escaped = try std.fmt.allocPrint(allocator, "\\x{x:0>2}", .{byte});
                try out.appendSlice(allocator, escaped);
            },
            else => try out.append(allocator, byte),
        }
    }
    return out.toOwnedSlice(allocator);
}

fn bytesToInt(bytes: []const u8) u128 {
    var value: u128 = 0;
    for (bytes) |byte| {
        value = (value << 8) | byte;
    }
    return value;
}

fn indented(allocator: std.mem.Allocator, indent: []const u8, extra: usize) ![]const u8 {
    var result = std.ArrayList(u8).empty;
    try result.appendSlice(allocator, indent);
    try result.appendNTimes(allocator, ' ', extra);
    return result.toOwnedSlice(allocator);
}

fn safeIdentifier(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    for (bytes) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '_') {
            try out.append(allocator, byte);
        } else {
            const escaped = try std.fmt.allocPrint(allocator, "_x{d}", .{byte});
            try out.appendSlice(allocator, escaped);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn expandGenerativeTerminal(allocator: std.mem.Allocator, out: *std.ArrayList([]const u8), id: []const u8) !void {
    if (std.mem.eql(u8, id, "digit")) return appendChars(allocator, out, "0123456789");
    if (std.mem.eql(u8, id, "letter")) return appendChars(allocator, out, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ");
    if (std.mem.eql(u8, id, "lowercase_letter")) return appendChars(allocator, out, "abcdefghijklmnopqrstuvwxyz");
    if (std.mem.eql(u8, id, "uppercase_letter")) return appendChars(allocator, out, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    if (std.mem.eql(u8, id, "new_line")) return out.append(allocator, "\n");
    if (std.mem.eql(u8, id, "space")) return out.append(allocator, " ");
    if (std.mem.eql(u8, id, "block_start")) return out.append(allocator, "\x01");
    if (std.mem.eql(u8, id, "block_end")) return out.append(allocator, "\x02");
    if (std.mem.startsWith(u8, id, "character")) return appendCharsExcept(allocator, out, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~ \t\n\r\x0b\x0c", id);
    if (std.mem.startsWith(u8, id, "whitespace")) return appendChars(allocator, out, " \t\n\r\x0b\x0c");
    if (std.mem.startsWith(u8, id, "punctuation")) return appendChars(allocator, out, "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~");
    if (std.mem.startsWith(u8, id, "operator")) {
        for (&[_][]const u8{ "+", "*", "/", "&", "|", ">", ">=", "<", "<=", "=" }) |op| try out.append(allocator, op);
        return;
    }
    return error.UnknownGenerativeTerminal;
}

fn appendChars(allocator: std.mem.Allocator, out: *std.ArrayList([]const u8), chars: []const u8) !void {
    for (chars) |char| {
        const item = try allocator.alloc(u8, 1);
        item[0] = char;
        try out.append(allocator, item);
    }
}

fn appendCharsExcept(allocator: std.mem.Allocator, out: *std.ArrayList([]const u8), chars: []const u8, id: []const u8) !void {
    var excluded = [_]bool{false} ** 256;
    var i = std.mem.indexOfScalar(u8, id, '^') orelse id.len;
    while (i < id.len) {
        i += 1;
        if (i >= id.len) break;
        const quote = id[i];
        i += 1;
        while (i < id.len and id[i] != quote and id[i] != 0x03) : (i += 1) excluded[id[i]] = true;
        if (i < id.len) i += 1;
    }
    for (chars) |byte| {
        if (!excluded[byte]) {
            const item = try allocator.alloc(u8, 1);
            item[0] = byte;
            try out.append(allocator, item);
        }
    }
}
