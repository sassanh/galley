from functools import cached_property

from base._zig import ParserGeneratorZigMixin
from data_structures import (
    TerminalSymbol,
    VariableSymbol,
)
from glr._data_structures import (
    AcceptResolution,
    GotoResolution,
    ReduceResolution,
    ShiftResolution,
)
from lr._parse_table import LRParserGeneratorParseTableMixin


class LRParserGeneratorZigMixin(
    LRParserGeneratorParseTableMixin,
    ParserGeneratorZigMixin,
):
    @cached_property
    def zig_parser(self) -> str:
        return f"""\
{self.zig_base}

const ResolutionType = enum {{
    shift,
    reduce,
    accept,
}};

const Resolution = struct {{
    type: ResolutionType,
    data_index: u16,
    symbol_index: u16,
}};

pub const action_table = blk: {{
    @setEvalBranchQuota(10_000_000);
    break :blk &[_]data_structures.StaticStringMap(Resolution){{
{
            "\n".join(
                [
                    f'''        data_structures.StaticStringMap(Resolution).initComptime(\
&[_]data_structures.StaticStringMap(Resolution).Entry{{{
                        "\n            ".join(
                            [""]
                            + [
                                f'.{{ "{
                                    self.token_repr(terminal_item)
                                }", Resolution{{ .type = .{
                                    resolution.type_string
                                }, .data_index = {
                                    self.canonical_state_indices[resolution.state]
                                    if isinstance(resolution, ShiftResolution)
                                    else self.rules_list.index(resolution.rule)
                                    if isinstance(resolution, ReduceResolution)
                                    else 0
                                    if isinstance(resolution, AcceptResolution)
                                    else 1 / 0
                                }, .symbol_index = {symbol.index} }} }},'
                                for terminal_item, symbol, resolution in sorted(
                                    (
                                        (
                                            terminal_item,
                                            symbol,
                                            resolution,
                                        )
                                        for symbol, resolution in self.lr_parse_table[
                                            state
                                        ].items()
                                        if isinstance(symbol, TerminalSymbol)
                                        for terminal_item in symbol.terminals
                                    ),
                                    key=lambda x: x[0],
                                )
                            ]
                        )
                    }
        }}), // {repr("")} {self.canonical_state_indices[state]}'''
                    for state in self.canonical_states
                ]
            )
        }
    }};
}};

pub const goto_table = blk: {{
    @setEvalBranchQuota(10_000_000);
    break :blk &[_]data_structures.StaticIntMap(u16, u16){{
{
            "\n".join(
                [
                    f'''        data_structures.StaticIntMap(u16, u16).initComptime(\
&[_]data_structures.StaticIntMap(u16, u16).Entry{{{
                        "\n".join(
                            [""]
                            + [
                                f"            .{{ {symbol.variable_index}, {
                                    self.canonical_state_indices[resolution.state]
                                    if isinstance(resolution, GotoResolution)
                                    else 1 / 0
                                } }},"
                                for symbol, resolution in self.lr_parse_table[
                                    state
                                ].items()
                                if isinstance(symbol, VariableSymbol)
                            ]
                            + (
                                ["        "]
                                if len(
                                    [
                                        symbol
                                        for symbol in self.lr_parse_table[state]
                                        if isinstance(symbol, VariableSymbol)
                                    ]
                                )
                                else []
                            )
                        )
                    }}}), // {repr("")} {self.canonical_state_indices[state]}'''
                    for state in self.canonical_states
                ]
            )
        }
    }};
}};"""
