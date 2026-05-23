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
            "break"
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

    def _varaible_case(
        self,
        variable: VariableSymbol,
        rhs: RightHandSide,
        *,
        self_repeating_index: int | None,
    ) -> str:
        symbols = rhs.symbols
        if not symbols:
            return ""

        if self_repeating_index is not None:
            symbols_left = symbols[:self_repeating_index]
            return "\n" + "\n".join(
                [
                    f"try parse_{_convert_to_safe_id(repr(rhs_symbol))}(context);"
                    for rhs_symbol in symbols_left
                ]
            )
        else:
            result = (
                "\n".join(
                    [
                        f"try parse_{_convert_to_safe_id(repr(rhs_symbol))}_{
                            self.rules[variable.id].index(rhs)
                        }_{rhs_index}(context);"
                        if rhs_symbol is variable
                        else f"try parse_{_convert_to_safe_id(repr(rhs_symbol))}(context);"
                        for rhs_index, rhs_symbol in enumerate(symbols)
                    ]
                )
                + "\n"
            )

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
            + f"""
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
        )

    def _terminal_case(self, length: int) -> str:
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
switch (context.head(u{key_length * 8}, {prefix_length}, {key_length})) {{
    {
            "\n    ".join(
                [
                    self._rule_cases(
                        terminals,
                        code
                        if (
                            code := (
                                self._varaible_case(
                                    symbol,
                                    outcome,
                                    self_repeating_index=self_repeating_index,
                                )
                                if isinstance(symbol, VariableSymbol)
                                else self._terminal_case(
                                    prefix_length
                                    if terminals == (b"",)
                                    else prefix_length + key_length
                                )
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
                            )
                        )
                        else "",
                    ).replace("\n", "\n    ")
                    for terminals, outcome in sorted(items.items())
                ]
            )
        }{
            self._switch_else(
                symbol, items, is_self_repeating=self_repeating_index is not None
            ).replace("\n", "\n    ")
            if not any(b"" in i for i in items.keys())
            else ""
        }
}}"""

    def _zig_reducer(self, symbol: Symbol) -> str:
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
                        result += f"""\
// Self-repeating parser for symbol "{repr(symbol)}" at index {
                            symbol.index
                        } of its right hand side
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
inline fn parse_{repr(symbol)}_{self.rules[variable.id].index(rhs)}_{
                            self_repeating_index
                        }(context: *data_structures.Context) error {{ StackOverflow, InvalidIndentation, SyntaxError }}!void {{
{
                            "    var counter: usize = 0;\n"
                            if len(rhs.symbols) > self_repeating_index + 1
                            else ""
                        }    while (true) {{
        {
                            self._rule_switch(
                                symbol,
                                rhs_items,
                                self_repeating_index=self_repeating_index,
                            ).replace("\n", "\n        ")
                        }
{"        counter += 1;\n" if len(rhs.symbols) > self_repeating_index + 1 else ""}    }}

    try parse_{_convert_to_safe_id(repr(variable))}(context);{
                            f'''
    for (0..counter) |_| {{
        {
                                "\n    ".join(
                                    [
                                        f"try parse_{_convert_to_safe_id(repr(rhs_symbol))}(context);"
                                        for rhs_symbol in rhs.symbols[
                                            self_repeating_index + 1 :
                                        ]
                                    ]
                                )
                            }
    }}
'''
                            if len(rhs.symbols) > self_repeating_index + 1
                            else ""
                        }
}}

"""
                except ValueError:
                    pass

        if not table:
            return ""

        items = _switch_dict(table)

        result += f"""\
// Parser for symbol "{repr(symbol)}" with index {symbol.index}
{"inline " if isinstance(symbol, TerminalSymbol) else ""}fn parse_{
            _convert_to_safe_id(repr(symbol))
        }(context: *data_structures.Context) error{{ StackOverflow, InvalidIndentation, SyntaxError }}!void {{
    {self._rule_switch(symbol, items).replace("\n", "\n    ")}
}}"""
        return result

    @cached_property
    def zig_parser(self) -> str:

        return f"""\
{self.zig_base}

{"\n\n".join([code for symbol in self.symbols if (code := self._zig_reducer(symbol))])}

pub fn parse(context: *data_structures.Context) !void {{
    parse_AugmentedStart(context) catch {{
        if (comptime builtin.mode == .Debug) {{
            return error.ParseError;
        }}
        context.parsed_bytes += context.seek;
        return;
    }};

    context.parsed_bytes += context.seek;
    if (context.verbosity > 0) {{
        std.log.info("The input file was parsed successfully!", .{{}});
    }}
}}"""
