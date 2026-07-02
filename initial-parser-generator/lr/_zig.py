from functools import cached_property

from base._zig import ParserGeneratorZigMixin, SwitchDict, _switch_dict
from data_structures import (
    GenerativeTerminalSymbol,
    Symbol,
    TerminalSymbol,
    VariableSymbol,
)
from glr._data_structures import (
    AcceptResolution,
    GotoResolution,
    ReduceResolution,
    Resolution,
    ShiftResolution,
    State,
)
from lr._parse_table import LRParserGeneratorParseTableMixin


class LRParserGeneratorZigMixin(
    LRParserGeneratorParseTableMixin,
    ParserGeneratorZigMixin,
):
    @cached_property
    def linked_terminals(self) -> set[bytes]:
        linked = set()
        for header, rhs in self.rules_list:
            variable = VariableSymbol(id=header)
            if variable.is_ast_enabled:
                for sym in rhs.symbols:
                    if isinstance(sym, TerminalSymbol):
                        linked.add(sym.id)
        return linked

    @cached_property
    def zig_parser(self) -> str:
        # Generate state functions
        state_functions = []
        for state in self.canonical_states:
            state_index = self.canonical_state_indices[state]

            # Action Switch Dict
            table: dict[bytes, tuple[Symbol, Resolution]] = {}
            for symbol, resolution in self.lr_parse_table[state].items():
                if isinstance(symbol, TerminalSymbol):
                    for terminal_item in symbol.terminals:
                        table[terminal_item] = (symbol, resolution)

            # Goto Table transitions for this state
            goto_cases = []
            for symbol, resolution in self.lr_parse_table[state].items():
                if isinstance(symbol, VariableSymbol) and isinstance(
                    resolution, GotoResolution
                ):
                    dest_state_index = self.canonical_state_indices[resolution.state]
                    goto_cases.append(
                        f"{symbol.variable_index} => try state_{dest_state_index}(context, stack),"
                    )

            # Action switch string
            action_items = _switch_dict(table)
            action_switch_str = self._lr_state_switch(state, action_items)

            # Goto loop string
            if goto_cases:
                goto_switch_cases = "\n            ".join(goto_cases)
                goto_loop_str = f"""
    while (true) {{
        if (result.is_accept) return result;
        if (result.pops_remaining > 0) {{
            result.pops_remaining -= 1;
            return result;
        }}
        result = switch (result.variable) {{
            {goto_switch_cases}
            else => unreachable,
        }};
    }}"""
            else:
                goto_loop_str = """
    while (true) {
        if (result.is_accept) return result;
        if (result.pops_remaining > 0) {
            result.pops_remaining -= 1;
            return result;
        }
        return error.SyntaxError;
    }"""

            # Construct state function
            stack_discard = (
                ""
                if "stack" in (action_switch_str + goto_loop_str)
                else "    _ = stack;\n"
            )
            state_functions.append(f"""\
fn state_{state_index}(context: *data_structures.Context, stack: *SemanticStack) anyerror!ReduceResult {{
{stack_discard}    var result: ReduceResult = undefined;
    {action_switch_str.replace("\n", "\n    ")}
    {goto_loop_str.replace("\n", "\n    ")}
}}""")

        state_functions_str = "\n\n".join(state_functions)

        return f"""\
{self.zig_base}

const ReduceResult = struct {{
    variable: u16,
    pops_remaining: u16,
    is_accept: bool,
}};

const SemanticStack = std.ArrayList(data_structures.ASTNode.Pointer);

{state_functions_str}

pub fn parse(context: *data_structures.Context) !void {{
    var stack: SemanticStack = .empty;
    defer stack.deinit(context.arena_allocator);

    const result = try state_0(context, &stack);
    if (!result.is_accept) {{
        return error.ParseError;
    }}

    if (context.verbosityLevel() > 0) {{
        std.log.info("The input file was parsed successfully!", .{{}});
    }}
}}"""

    def _lr_state_switch(
        self,
        state: State,
        items: SwitchDict[tuple[Symbol, Resolution]],
        prefix_length: int = 0,
    ) -> str:
        if not items:
            expected_terminals = []
            state_index = self.canonical_state_indices[state]
            return self._lr_syntax_error_block(state_index, expected_terminals)

        sample_key = next(
            iter(
                terminal
                for terminals in items.keys()
                for terminal in terminals
                if terminal != b""
            ),
            None,
        )
        key_length = len(sample_key) if sample_key is not None else 1

        cases_code = []
        for terminals, outcome in sorted(items.items()):
            # Generate code for the outcome
            if isinstance(outcome, tuple):
                # We have reached a leaf!
                symbol, resolution = outcome
                code = self._lr_action_code(
                    symbol,
                    resolution,
                    prefix_length + key_length
                    if terminals != (b"",)
                    else prefix_length,
                )
            else:
                # Nested switch dict
                code = "\n" + self._lr_state_switch(
                    state,
                    outcome,
                    prefix_length
                    if terminals == (b"",)
                    else prefix_length + key_length,
                )

            case_label = (
                "else"
                if terminals == (b"",)
                else ", ".join(str(int.from_bytes(term)) for term in terminals)
            )
            terminals_repr = ", ".join(
                f"'{self.token_repr(term)}'" for term in terminals
            )
            cases_code.append(f"""{case_label} => {{ // {terminals_repr}
    {code.replace("\n", "\n    ")}
}},""")

        # Determine else branch
        has_else = any(terminals == (b"",) for terminals in items.keys())
        else_branch = ""
        if not has_else:
            expected_terminals = sorted(
                list(
                    set(
                        terminal_item
                        for symbol, _ in self.lr_parse_table[state].items()
                        if isinstance(symbol, TerminalSymbol)
                        for terminal_item in symbol.terminals
                    )
                )
            )
            state_index = self.canonical_state_indices[state]
            else_branch = (
                "\nelse => "
                + self._lr_syntax_error_block(state_index, expected_terminals).replace(
                    "\n", "\n    "
                )
                + ","
            )

        cases_joined = "\n".join(cases_code)

        return f"""switch (context.head(u{key_length * 8}, {prefix_length})) {{
    {cases_joined}
    {else_branch}
}}"""

    def _lr_syntax_error_block(
        self, state_index: int, expected_terminals: list[bytes]
    ) -> str:
        expected_str = b"', '".join(expected_terminals)
        expected_str_repr = self.token_repr(expected_str, in_format_string=True)
        return f"""{{
    std.debug.print("\\x1b[35mSyntaxError at {{d}}:{{d}}:\\n\\x1b[37mUnexpected token \\x1b[31m\\"{{f}}\\"\\x1b[37m in state {state_index}.\\nExpected tokens: \\x1b[32m\\'{expected_str_repr}\\'\\x1b[0m\\n", .{{
        if (comptime builtin.mode != .ReleaseFast) context.line else 0,
        if (comptime builtin.mode != .ReleaseFast) context.column else 0,
        string_utilities.fmtString(context.token.items()),
    }});
    return error.SyntaxError;
}}"""

    def _lr_action_code(
        self, symbol: Symbol, resolution: Resolution, length: int
    ) -> str:
        if isinstance(resolution, ShiftResolution):
            dest_state_index = self.canonical_state_indices[resolution.state]
            ast_push = ""
            procedure_call = ""
            if self.with_ast:
                if self.ast_for_terminals and (symbol.id in self.linked_terminals):
                    ast_push = f"""const node_address = context.node_allocator.create(context.pos(), data_structures.ASTNode.invalid_variable);
context.node_allocator.at(node_address).text_length = {length};
try stack.append(context.arena_allocator, node_address);
"""
                    if self.with_procedures:
                        if isinstance(symbol, GenerativeTerminalSymbol):
                            procedure_call = f"""var args = data_structures.ProcedureArguments{{
    .context = context,
    .rule = null,
    .node = node_address,
}};
if (comptime symbol_procedures[{symbol.index}]) |procedure_pointer| {{
    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
    try procedure(&args);
}}
if (comptime reduction_procedure) |procedure_pointer| {{
    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
    try procedure(&args);
}}
"""
                else:
                    ast_push = f"""try stack.append(context.arena_allocator, context.pos());
"""
            release = f"context.release_token({length});"
            debug_print = f"""
if (comptime builtin.mode == .Debug) {{
    if (context.verbosityLevel() > 1) {{
        std.debug.print("Shift: matched '{{s}}', transitioning to state_{dest_state_index}\\n", .{{"{self.token_repr(symbol.id)}"}});
    }}
}}
"""
            return f"""{ast_push}{release}
{procedure_call}{debug_print}result = try state_{dest_state_index}(context, stack);"""

        elif isinstance(resolution, ReduceResolution):
            rule_index = self.rules_list.index(resolution.rule)
            return self._generate_reduce_code(rule_index)

        elif isinstance(resolution, AcceptResolution):
            debug_print = """
if (comptime builtin.mode == .Debug) {
    if (context.verbosityLevel() > 1) {
        std.debug.print("Accept!\\n", .{});
    }
}
"""
            return f"""{debug_print}return ReduceResult{{ .variable = 0, .pops_remaining = 0, .is_accept = true }};"""

        else:
            raise ValueError(f"Unknown resolution type: {type(resolution)}")

    def _generate_reduce_code(self, rule_index: int) -> str:
        header, rhs = self.rules_list[rule_index]
        variable = VariableSymbol(id=header)
        variable_index = variable.variable_index
        symbol_index = variable.index
        rhs_len = len(rhs.symbols)

        def symbol_is_linked(sym):
            if isinstance(sym, VariableSymbol):
                return sym.is_ast_enabled
            elif isinstance(sym, TerminalSymbol):
                return self.ast_for_terminals and (sym.id in self.linked_terminals)
            return False

        if self.with_ast:
            # Pop in reverse order, discarding unlinked nodes (except child_1 which is used for start_pos)
            pop_code = ""
            for i in reversed(range(rhs_len)):
                sym = rhs.symbols[i]
                is_linked = symbol_is_linked(sym)
                is_needed = (is_linked and variable.is_ast_enabled) or (i == 0)
                if is_needed:
                    pop_code += f"const child_{i + 1} = stack.pop().?;\n"
                else:
                    pop_code += "_ = stack.pop();\n"

            if rhs_len > 0:
                first_sym = rhs.symbols[0]
                if symbol_is_linked(first_sym):
                    start_pos_code = "const start_pos = context.node_allocator.at(child_1).text_start;"
                else:
                    start_pos_code = "const start_pos = child_1;"
            else:
                start_pos_code = "const start_pos = context.pos();"

            if variable.is_ast_enabled:
                insert_code = ""
                for i in range(rhs_len):
                    sym = rhs.symbols[i]
                    if symbol_is_linked(sym):
                        insert_code += f"context.node_allocator.at(parent_address).immediate_insert_child(parent_address, child_{i + 1}, context);\n"

                procedure_code = ""
                if self.with_procedures:
                    procedure_code = f"""
        var args = data_structures.ProcedureArguments{{
            .context = context,
            .rule = rules[{rule_index}],
            .node = parent_address,
        }};
        if (comptime rule_procedures[{rule_index}]) |procedure_pointer| {{
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }}
        comptime var procedure_pointer_head = variable_procedures[{variable_index}];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {{
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }}
        if (comptime symbol_procedures[{symbol_index}]) |procedure_pointer| {{
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }}
        if (comptime reduction_procedure) |procedure_pointer| {{
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }}
"""
                debug_code = f"""
        if (comptime builtin.mode == .Debug) {{
            if (context.verbosityLevel() > 1) {{
                std.debug.print("Reduction: {{s}} <~ ...\\n", .{{"{variable.printable}"}});
            }}
        }}
"""

                stack_push_address = (
                    "args.node orelse data_structures.ASTNode.invalid_pointer"
                    if self.with_procedures
                    else "parent_address"
                )
                return f"""{{
        {pop_code}
        {start_pos_code}
        const parent_address = context.node_allocator.create(start_pos, {variable_index});
        {insert_code}
        {procedure_code}
        try stack.append(context.arena_allocator, {stack_push_address});
        {debug_code}
        {"return" if rhs_len > 0 else "result ="} ReduceResult{{ .variable = {variable_index}, .pops_remaining = {max(0, rhs_len - 1)}, .is_accept = false }};
    }}"""
            else:
                # If variable has is_ast_enabled = False, we don't allocate a parent node.
                # We just run procedures if any, and push start_pos directly to the stack.
                procedure_code = ""
                if self.with_procedures:
                    procedure_code = f"""
        var args = data_structures.ProcedureArguments{{
            .context = context,
            .rule = rules[{rule_index}],
            .node = data_structures.ASTNode.invalid_pointer,
        }};
        if (comptime rule_procedures[{rule_index}]) |procedure_pointer| {{
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }}
        comptime var procedure_pointer_head = variable_procedures[{variable_index}];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {{
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }}
        if (comptime symbol_procedures[{symbol_index}]) |procedure_pointer| {{
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }}
        if (comptime reduction_procedure) |procedure_pointer| {{
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }}
"""
                debug_code = f"""
        if (comptime builtin.mode == .Debug) {{
            if (context.verbosityLevel() > 1) {{
                std.debug.print("Reduction (no AST): {{s}} <~ ...\\n", .{{"{variable.printable}"}});
            }}
        }}
"""
                stack_push_value = (
                    "args.node orelse start_pos"
                    if self.with_procedures
                    else "start_pos"
                )
                return f"""{{
        {pop_code}
        {start_pos_code}
        {procedure_code}
        try stack.append(context.arena_allocator, {stack_push_value});
        {debug_code}
        {"return" if rhs_len > 0 else "result ="} ReduceResult{{ .variable = {variable_index}, .pops_remaining = {max(0, rhs_len - 1)}, .is_accept = false }};
    }}"""
        else:
            return f"""{"return" if rhs_len > 0 else "result ="} ReduceResult{{ .variable = {variable_index}, .pops_remaining = {max(0, rhs_len - 1)}, .is_accept = false }};"""
