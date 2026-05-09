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
from glr._parse_table import GLRParserGeneratorParseTableMixin


class GLRParserGeneratorZigMixin(
    GLRParserGeneratorParseTableMixin,
    ParserGeneratorZigMixin,
):
    @cached_property
    def zig_parse_table(self) -> str:
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
                                }", &[_]Resolution{{ {
                                    ", ".join(
                                        f"Resolution{{.type = .{
                                            resolution.type_string
                                        }, .data_index = {
                                            self.canonical_state_indices[
                                                resolution.state
                                            ]
                                            if isinstance(resolution, ShiftResolution)
                                            else self.rules_list.index(resolution.rule)
                                            if isinstance(resolution, ReduceResolution)
                                            else 0
                                            if isinstance(resolution, AcceptResolution)
                                            else print(resolution) or 1 / 0
                                        }, .symbol_index = {symbol.index} }}"
                                        for resolution in resolutions
                                    )
                                } }} }},'
                                for terminal_item, symbol, resolutions in sorted(
                                    (
                                        (
                                            terminal_item,
                                            symbol,
                                            resolution,
                                        )
                                        for symbol, resolution in self.parse_table[
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
    break :blk &[_]data_structures.StaticIntMap(u16, []const u16){{
{
            "\n".join(
                [
                    f'''        data_structures.StaticIntMap(u16, []const u16).initComptime(.{{{
                        "\n            ".join(
                            [""]
                            + [
                                f".{{ {symbol.index}, &[_]u16{{ {
                                    ', '.join(
                                        str(
                                            self.canonical_state_indices[
                                                resolution.state
                                            ]
                                            if isinstance(resolution, GotoResolution)
                                            else 1 / 0
                                        )
                                        for resolution in resolutions
                                    )
                                } }} }},"
                                for symbol, resolutions in self.parse_table[
                                    state
                                ].items()
                                if isinstance(symbol, VariableSymbol)
                            ]
                        )
                    }
        }}), // {repr("")} {self.canonical_state_indices[state]}'''
                    for state in self.canonical_states
                ]
            )
        }
    }};
}};"""
