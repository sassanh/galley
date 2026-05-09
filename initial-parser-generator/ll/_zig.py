from functools import cached_property

from base._zig import ParserGeneratorZigMixin
from data_structures import RightHandSide, TerminalSymbol
from ll._parse_table import LLParserGeneratorParseTableMixin


class LLParserGeneratorZigMixin(
    LLParserGeneratorParseTableMixin,
    ParserGeneratorZigMixin,
):
    generative_terminal_id: bytes

    @cached_property
    def zig_parse_table(self) -> str:
        return f"""\
{self.zig_base}

pub const parse_table = blk: {{
    @setEvalBranchQuota(200_000);
    break :blk [_]std.StaticStringMap(usize){{
{
            "\n".join(
                [
                    f'''        std.StaticStringMap(usize).initComptime(.{{{
                        "\n            ".join(
                            [""]
                            + [
                                f'.{{ "{self.token_repr(terminal_item)}", {
                                    self.rules_list.index(rule)
                                }}},'
                                for terminal_item, rule in (
                                    (
                                        (
                                            terminal_item,
                                            (
                                                self.generative_terminal_id,
                                                RightHandSide([]),
                                            ),
                                        )
                                        for terminal_item in symbol.terminals
                                    )
                                    if isinstance(symbol, TerminalSymbol)
                                    else (
                                        (terminal_item, rule)
                                        for terminal, rule in self.parse_table[
                                            symbol
                                        ].items()
                                        for terminal_item in terminal.terminals
                                    )
                                )
                            ]
                        )
                    }
        }}), // {repr(symbol)} {symbol.index}'''
                    for symbol in self.symbols
                ]
            )
        }
    }};
}};"""
