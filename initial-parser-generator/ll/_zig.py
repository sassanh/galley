import re
from collections import defaultdict
from functools import cached_property

from base._zig import ParserGeneratorZigMixin
from data_structures import RightHandSide, Symbol, TerminalSymbol, VariableSymbol
from ll._parse_table import LLParserGeneratorParseTableMixin


def _convert_to_safe_id(text: str) -> str:
    result = []

    for char in text:
        if char.isalnum() or char == "_":
            result.append(char)
        else:
            result.append(f"_x{ord(char)}")

    return "".join(result)


type SwitchDict[T] = dict[tuple[bytes, ...], SwitchDict[T] | T]


def _switch_dict(
    table: dict[bytes, RightHandSide],
) -> SwitchDict[RightHandSide]:
    items: dict[bytes, set[tuple[bytes, bool, RightHandSide]]] = defaultdict(set)
    payload_lookup: dict[tuple[tuple[bytes, bool, RightHandSide], ...], set[bytes]] = (
        defaultdict(set)
    )

    step_length = min(length for terminal in table if (length := len(terminal)))

    for terminal, rhs in table.items():
        items[terminal[:step_length]].add(
            (terminal[step_length:], len(terminal[:step_length]) > 0, rhs)
        )

    for head, payload in items.items():
        payload_lookup[tuple(sorted(payload))].add(head)

    return {
        tuple(sorted(heads)): logic_payload[0][2]
        if len(logic_payload) <= 1 and len(logic_payload[0][0]) == 0
        else _switch_dict({terminal: rule for terminal, _, rule in logic_payload})
        for logic_payload, heads in payload_lookup.items()
    }


class LLParserGeneratorZigMixin(
    LLParserGeneratorParseTableMixin,
    ParserGeneratorZigMixin,
):
    _generative_terminal_id: bytes

    def __init__(self) -> None:
        self._needing_non_ast_mode: set[Symbol] = set()
        super().__init__()

    def patch_grammar(self):
        self._generative_terminal_id = b"GenerativeTerminal"
        self.rules[self._generative_terminal_id].append(RightHandSide(()))
        self.symbols.append(VariableSymbol(id=self._generative_terminal_id))

    def _switch_else(
        self,
        symbol: Symbol,
        items: SwitchDict[RightHandSide],
        *,
        is_self_repeating: bool,
    ) -> str:
        return "\nelse => " + (
            "break,"
            if is_self_repeating
            else f"""{{
    std.debug.print("\\x1b[35mSyntaxError at {{d}}:{{d}}:\\n\\x1b[37mUnexpected token \\x1b[31m\\"{{f}}\\"\\x1b[37m while parsing \\x1b[34m{
                self.token_repr(symbol.id, in_format_string=True)
            }\\x1b[0m.\\nExpected tokens: \\x1b[32m\\'{
                self.token_repr(
                    b"', '".join(
                        sorted(
                            terminal_item
                            for terminal in items
                            for terminal_item in terminal
                        ),
                    ),
                    in_format_string=True,
                )
            }\\'\\x1b[0m\\n", .{{
        context.line,
        context.column,
        string_utilities.fmtString(context.token.items()),
    }});
    return error.SyntaxError;
}},"""
        )

    def _ast_node_logic(
        self,
        node_name,
        symbol: Symbol,
        rhs: RightHandSide,
        *,
        non_ast: bool,
    ):
        if not self.with_procedures or not self.with_ast or non_ast:
            return ""
        return f"""
var args = data_structures.ProcedureArguments{{
    .context = context,
    .rule = {
            f"rules[{self.rules_list.index((variable.id, rhs))}]"
            if isinstance(variable := symbol, VariableSymbol)
            else "null"
        },
    .node = {node_name},
}};
{
            f'''
if (comptime rule_procedures[{
                self.rules_list.index((variable.id, rhs))
            }]) |procedure_pointer| {{
    const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
    try procedure(&args);
}}

'''
            if isinstance(variable := symbol, VariableSymbol)
            else ""
        }{
            f'''
comptime var procedure_pointer_head = variable_procedures[{variable.variable_index}];
inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {{
    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
    try procedure(&args);
    procedure_pointer_head = procedure_pointer_head_.next;
}}'''
            if isinstance(variable := symbol, VariableSymbol)
            else ""
        }

if (comptime symbol_procedures[{symbol.index}]) |procedure_pointer| {{
    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
    try procedure(&args);
}}

if (comptime reduction_procedure) |procedure_pointer| {{
    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
    try procedure(&args);
}}

if (comptime builtin.mode == .Debug) {{
    if (context.verbosity > 2) {{
        std.debug.print("Procedure outcome for {
            self.token_repr(symbol.id, in_format_string=True)
        }: {{f}}\\n", .{{
            string_utilities.fmtASTNode(args.node, context),
        }});
    }}
}}
"""

    def _add_child_line(
        self,
        rhs_symbol: Symbol,
        *,
        rhs_symbol_index: int,
        parent: str,
        parent_address: str,
        variable: VariableSymbol | None = None,
        symbols: tuple[Symbol, ...],
        rhs_index: int,
        non_ast: bool,
        child: str | None = None,
    ):
        if (
            self.with_ast
            and not non_ast
            and (self.ast_for_terminals or isinstance(rhs_symbol, VariableSymbol))
        ):
            if rhs_symbol.is_ast_enabled:
                ast_enabled_symbols: list[int] = []
                ast_enabled_symbols_counter = 0
                for symbol in symbols:
                    ast_enabled_symbols.append(ast_enabled_symbols_counter)
                    if symbol.is_ast_enabled:
                        ast_enabled_symbols_counter += 1
                if rhs_symbol is variable:
                    return f"{parent}.immediate_insert_child({parent_address}, {
                        f'try parse_{_convert_to_safe_id(repr(rhs_symbol))}_{
                            rhs_index
                        }_{rhs_symbol_index}(context)'
                        if child is None
                        else child
                    }, context); // child {rhs_symbol_index}"
                else:
                    return f"{parent}.immediate_insert_child({parent_address}, {
                        f'try parse_{_convert_to_safe_id(repr(rhs_symbol))}(context)'
                        if child is None
                        else child
                    }, context); // child {rhs_symbol_index}"

            else:
                return f"try parse_{_convert_to_safe_id(repr(rhs_symbol))}_{rhs_index}_{
                    rhs_symbol_index
                }(context); // child {rhs_symbol_index}"
        else:
            return (
                f"try parse_{_convert_to_safe_id(repr(rhs_symbol))}_{rhs_index}_{
                    rhs_symbol_index
                }{
                    self._needing_non_ast_mode.add(variable) or '_' if non_ast else ''
                }(context); // child {rhs_symbol_index}"
                if rhs_symbol is variable
                else f"try parse_{_convert_to_safe_id(repr(rhs_symbol))}{
                    self._needing_non_ast_mode.add(rhs_symbol) or '_' if non_ast else ''
                }(context); // child {rhs_symbol_index}"
            )

    def _variable_case(
        self,
        variable: VariableSymbol,
        rhs: RightHandSide,
        *,
        self_repeating_index: int | None,
        non_ast: bool,
    ) -> str:
        symbols = rhs.symbols
        if not symbols:
            return ""

        if self_repeating_index is not None:
            symbols_left = symbols[:self_repeating_index]
            result = (
                (
                    f"""\
const temporary_address = context.node_allocator.create(context.pos(), {
                        variable.variable_index
                    });
if (node_address == data_structures.ASTNode.invalid_pointer) {{
    node_address = temporary_address;
}} else {{
    {
                        self._add_child_line(
                            symbols[self_repeating_index],
                            rhs_symbol_index=self_repeating_index,
                            parent="repeating_node",
                            parent_address="repeating_node_address",
                            symbols=symbols[: self_repeating_index + 1],
                            variable=variable,
                            rhs_index=self.rules[variable.id].index(rhs),
                            non_ast=non_ast,
                            child="temporary_address",
                        )
                    }
}}
repeating_node_address = temporary_address;
repeating_node = context.node_allocator.at(repeating_node_address);
"""
                    + "\n".join(
                        self._add_child_line(
                            rhs_symbol,
                            rhs_symbol_index=rhs_index,
                            parent="repeating_node",
                            parent_address="repeating_node_address",
                            symbols=symbols_left,
                            variable=variable,
                            rhs_index=self.rules[variable.id].index(rhs),
                            non_ast=non_ast,
                        )
                        for rhs_index, rhs_symbol in enumerate(symbols_left)
                    )
                )
                if self.with_ast and variable.is_ast_enabled and not non_ast
                else "\n".join(
                    self._needing_non_ast_mode.add(rhs_symbol)
                    or f"try parse_{
                        _convert_to_safe_id(repr(rhs_symbol))
                    }_(context); // child {rhs_index}"
                    for rhs_index, rhs_symbol in enumerate(symbols_left)
                )
                if self.with_ast and not non_ast
                else "\n".join(
                    f"try parse_{_convert_to_safe_id(repr(rhs_symbol))}{
                        self._needing_non_ast_mode.add(variable) or '_'
                        if non_ast
                        else ''
                    }(context); // child {rhs_index}"
                    for rhs_index, rhs_symbol in enumerate(symbols_left)
                )
            ) + (
                ""
                if self.with_ast and variable.is_ast_enabled and not non_ast
                else "\ncounter += 1;"
                if len(rhs.symbols) > self_repeating_index + 1
                else ""
            )
        else:
            result = (
                "\n".join(
                    self._add_child_line(
                        rhs_symbol,
                        rhs_symbol_index=rhs_index,
                        parent="context.node_allocator.at(node_address)",
                        parent_address="node_address",
                        symbols=symbols,
                        variable=variable,
                        rhs_index=self.rules[variable.id].index(rhs),
                        non_ast=non_ast,
                    )
                    for rhs_index, rhs_symbol in enumerate(symbols)
                )
            ) + self._ast_node_logic("node_address", variable, rhs, non_ast=non_ast)

        return (
            f"""
if (comptime builtin.mode == .Debug) {{
    if (context.verbosity > 1) {{
        std.debug.print("Rule expansion: {repr(variable)} -> {
                ", ".join(
                    [
                        f"'{self.token_repr(symbol.id, in_format_string=True)}'"
                        if isinstance(symbol, TerminalSymbol)
                        else self.token_repr(symbol.id)
                        for symbol in symbols
                    ]
                )
            }\\n", .{{}});
    }}
}}
"""
            + result
            + (
                f"""
if (comptime builtin.mode == .Debug) {{
    if (context.verbosity > 1) {{
        std.debug.print("Reduction: {repr(variable)} <~ {
                    ", ".join(
                        [
                            f"'{self.token_repr(symbol.id, in_format_string=True)}'"
                            if isinstance(symbol, TerminalSymbol)
                            else self.token_repr(symbol.id)
                            for symbol in symbols
                        ]
                    )
                }\\n", .{{}});
    }}
}}"""
                if self_repeating_index is None
                else ""
            )
        )

    def _terminal_case(
        self,
        length: int,
        terminal: TerminalSymbol,
        rhs: RightHandSide,
        *,
        non_ast: bool,
    ) -> str:
        if self.with_ast and not non_ast:
            return f"""
// node.text_length = {length};
context.release_token({length});""" + (
                self._ast_node_logic(
                    "node_address",
                    terminal,
                    rhs,
                    non_ast=non_ast,
                )
                if self.ast_for_terminals
                else ""
            )

        return f"\ncontext.release_token({length});"

    def _rule_cases(
        self,
        terminals: tuple[bytes, ...],
        code: str,
    ) -> str:
        return f"""{
            "else"
            if terminals == (b"",)
            else ", ".join(
                str(int.from_bytes(terminal_item)) for terminal_item in terminals
            )
        } => {{ // {
            ", ".join(f"'{self.token_repr(terminal)}'" for terminal in terminals)
        }{code.replace("\n", "\n    ")}
}},"""

    def _rule_switch(
        self,
        symbol: Symbol,
        items: SwitchDict[RightHandSide],
        prefix_length: int = 0,
        *,
        self_repeating_index: int | None = None,
        non_ast: bool,
    ) -> str:
        sample_key = next(
            iter(
                terminal
                for terminals in items.keys()
                for terminal in terminals
                if terminal != b""
            )
        )
        key_length = len(sample_key)
        return f"""\
switch (context.head(u{key_length * 8}, {prefix_length})) {{
    {
            "\n    ".join(
                self._rule_cases(
                    terminals,
                    code
                    if (
                        code := (
                            self._variable_case(
                                symbol,
                                outcome,
                                self_repeating_index=self_repeating_index,
                                non_ast=non_ast,
                            )
                            if isinstance(symbol, VariableSymbol)
                            else self._terminal_case(
                                prefix_length
                                if terminals == (b"",)
                                else prefix_length + key_length,
                                symbol,
                                outcome,
                                non_ast=non_ast,
                            )
                            if isinstance(symbol, TerminalSymbol)
                            else ""
                        )
                        if isinstance(outcome, RightHandSide)
                        else "\n"
                        + self._rule_switch(
                            symbol,
                            outcome,
                            prefix_length
                            if terminals == (b"",)
                            else prefix_length + key_length,
                            self_repeating_index=self_repeating_index,
                            non_ast=non_ast,
                        )
                    )
                    else "",
                ).replace("\n", "\n    ")
                for terminals, outcome in sorted(items.items())
            )
        }{
            self._switch_else(
                symbol, items, is_self_repeating=self_repeating_index is not None
            ).replace("\n", "\n    ")
            if not any(b"" in i for i in items.keys())
            else ""
        }
}}"""

    def _zig_reducer(self, symbol: Symbol, *, non_ast: bool = False) -> str:
        result = ""

        if isinstance(terminal := symbol, TerminalSymbol):
            table = {
                terminal_item: RightHandSide(symbols=())
                for terminal_item in terminal.terminals
            }
        elif isinstance(variable := symbol, VariableSymbol):
            parse_table_entry = self.parse_table[variable]
            table = {
                terminal_item: rhs
                for terminal, rhs in parse_table_entry.items()
                for terminal_item in terminal.terminals
            }

            rhs_lookup: dict[RightHandSide, set[bytes]] = defaultdict(set)
            for terminal, rhs in parse_table_entry.items():
                if variable in rhs.symbols:
                    rhs_lookup[rhs] |= {*terminal.terminals}

            for rhs, terminal_items in rhs_lookup.items():
                rhs_table = {terminal_item: rhs for terminal_item in terminal_items}
                rhs_items = _switch_dict(rhs_table)
                self_repeating_index = -1
                try:
                    while True:
                        self_repeating_index = rhs.symbols.index(
                            variable, self_repeating_index + 1
                        )
                        result += (
                            f"""\
// {"Non-AST " if non_ast else ""}Self-Repeating Parser for Symbol "{
                                repr(symbol)
                            }" at index {self_repeating_index} of its right hand side
// Right hand side: -> {
                                ", ".join(
                                    [
                                        f"'{self.token_repr(symbol.id, in_format_string=True)}'"
                                        if isinstance(symbol, TerminalSymbol)
                                        else self.token_repr(symbol.id)
                                        for symbol in rhs.symbols
                                    ]
                                )
                            }
fn parse_{repr(symbol)}_{self.rules[variable.id].index(rhs)}_{self_repeating_index}{
                                "_" if non_ast else ""
                            }(context: *data_structures.Context) anyerror!{
                                "data_structures.ASTNode.Pointer"
                                if self.with_ast
                                and variable.is_ast_enabled
                                and not non_ast
                                else "void"
                            } {{
"""
                            + (
                                """\
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;
"""
                                if self.with_ast
                                and not non_ast
                                and variable.is_ast_enabled
                                else """
    var counter: usize = 0;
"""
                                if len(rhs.symbols) > self_repeating_index + 1
                                else ""
                            )
                            + f"""
    while (true) {{
        {
                                self._rule_switch(
                                    symbol,
                                    rhs_items,
                                    self_repeating_index=self_repeating_index,
                                    non_ast=non_ast,
                                ).replace("\n", "\n        ")
                            }
    }}
"""
                            + (
                                f"""\
    const exit_node = try parse_{repr(symbol)}(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {{
        node_address = exit_node;
    }} else {{
        {
                                    self._add_child_line(
                                        rhs.symbols[self_repeating_index],
                                        rhs_symbol_index=self_repeating_index,
                                        parent="repeating_node",
                                        parent_address="repeating_node_address",
                                        symbols=rhs.symbols,
                                        variable=variable,
                                        rhs_index=self.rules[variable.id].index(rhs),
                                        non_ast=non_ast,
                                        child="exit_node",
                                    )
                                }
    }}
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {{
        repeating_node = context.node_allocator.at(repeating_node_address);
        {
                                    "\n        ".join(
                                        self._add_child_line(
                                            rhs_symbol,
                                            rhs_symbol_index=rhs_index
                                            + self_repeating_index
                                            + 1,
                                            parent="repeating_node",
                                            parent_address="repeating_node_address",
                                            symbols=rhs.symbols,
                                            variable=variable,
                                            rhs_index=self.rules[variable.id].index(
                                                rhs
                                            ),
                                            non_ast=non_ast,
                                        )
                                        for rhs_index, rhs_symbol in enumerate(
                                            rhs.symbols[self_repeating_index + 1 :]
                                        )
                                    )
                                    if len(rhs.symbols) > self_repeating_index + 1
                                    else ""
                                }
{
                                    f'''
        if (comptime builtin.mode == .Debug) {{
            if (context.verbosity > 1) {{
                std.debug.print("Reduction: {repr(variable)} <~ {
                                        ", ".join(
                                            [
                                                f"'{self.token_repr(symbol.id, in_format_string=True)}'"
                                                if isinstance(symbol, TerminalSymbol)
                                                else self.token_repr(symbol.id)
                                                for symbol in rhs.symbols
                                            ]
                                        )
                                    }\\n", .{{}});
            }}
        }}'''
                                }
                        {
                                    self._ast_node_logic(
                                        "repeating_node_address",
                                        variable,
                                        rhs,
                                        non_ast=non_ast,
                                    ).replace("\n", "\n        ")
                                }
        repeating_node_address = repeating_node.parent;
    }}
    return node_address;
"""
                                if self.with_ast
                                and variable.is_ast_enabled
                                and not non_ast
                                else self._needing_non_ast_mode.add(variable)
                                or f"""\
    try parse_{_convert_to_safe_id(repr(variable))}_(context);
"""
                                if self.with_ast and not non_ast
                                else f"""\
    try parse_{_convert_to_safe_id(repr(variable))}{
                                    self._needing_non_ast_mode.add(variable) or "_"
                                    if non_ast
                                    else ""
                                }(context);
"""
                                + (
                                    f"""
    for (0..counter) |_| {{
        {
                                        "\n        ".join(
                                            [
                                                f"try parse_{
                                                    _convert_to_safe_id(
                                                        repr(rhs_symbol)
                                                    )
                                                }{
                                                    self._needing_non_ast_mode.add(
                                                        variable
                                                    )
                                                    or '_'
                                                    if non_ast
                                                    else ''
                                                }(context); // child {
                                                    self_repeating_index + 1 + rhs_index
                                                }"
                                                for rhs_index, rhs_symbol in enumerate(
                                                    rhs.symbols[
                                                        self_repeating_index + 1 :
                                                    ]
                                                )
                                            ]
                                        )
                                    }
    }}
"""
                                    if len(rhs.symbols) > self_repeating_index + 1
                                    else ""
                                )
                            )
                            + """\
}

"""
                        )
                except ValueError:
                    pass

        if not table:
            return ""

        items = _switch_dict(table)

        result += f"""\
// {"Non-AST " if non_ast else ""}Parser for Symbol "{repr(symbol)}" with index {
            symbol.index
        }
{"inline " if isinstance(symbol, TerminalSymbol) else ""}fn parse_{
            _convert_to_safe_id(repr(symbol))
        }{"_" if non_ast else ""}(context: *data_structures.Context) anyerror!{
            "data_structures.ASTNode.Pointer"
            if self.with_ast
            and not non_ast
            and (self.ast_for_terminals or isinstance(symbol, VariableSymbol))
            else "void"
        } {{{
            f'''
    const node_address = context.node_allocator.create(context.pos(), {
                variable.variable_index
                if isinstance(variable := symbol, VariableSymbol)
                else "data_structures.ASTNode.invalid_variable"
            });
'''
            if self.with_ast
            and not non_ast
            and (self.ast_for_terminals or isinstance(symbol, VariableSymbol))
            else ""
        }
    {self._rule_switch(symbol, items, non_ast=non_ast).replace("\n", "\n    ")}{
            "\n    return node_address;"
            if self.with_ast
            and not non_ast
            and (self.ast_for_terminals or isinstance(symbol, VariableSymbol))
            else ""
        }
}}"""
        return re.sub(r"\n\s+\n", "\n\n", result)

    @cached_property
    def zig_parser(self) -> str:

        return f"""\
{self.zig_base}

{"\n\n".join([code for symbol in self.symbols if (code := self._zig_reducer(symbol))])}
{self._non_ast_parsers()}

pub fn parse(context: *data_structures.Context) !void {{
    _ = parse_AugmentedStart(context) catch {{
        if (comptime builtin.mode == .Debug) {{
            return error.ParseError;
        }}
        return;
    }};

    if (context.verbosity > 0) {{
        std.log.info("The input file was parsed successfully!", .{{}});
    }}
}}"""

    def _non_ast_parsers(self) -> str:
        generated_parsers: set[Symbol] = set()
        result = ""
        while self._needing_non_ast_mode - generated_parsers:
            for symbol in self._needing_non_ast_mode - generated_parsers:
                generated_parsers.add(symbol)
                if code := self._zig_reducer(symbol, non_ast=True):
                    result += "\n\n" + code

        return result
