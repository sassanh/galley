from functools import cached_property

from base import ParserGeneratorBaseMixin
from data_structures import (
    GenerativeTerminalSymbol,
    TerminalSymbol,
    VariableSymbol,
)


class ParserGeneratorZigMixin(ParserGeneratorBaseMixin):
    def token_repr(self, token: bytes) -> str:
        return (
            token.decode("raw-unicode-escape")
            .encode("unicode-escape")
            .decode("utf-8")
            .replace('"', '\\"')
        )

    @cached_property
    def zig_base(self):
        return f"""\
const std = @import("std");
const data_structures = @import("root").data_structures;
const parser = @import("parser");

pub const parse_table_type = "{self.parser_type}";

pub const symbols = &[_][]const u8{{
    {
            "\n    ".join(
                [f'"{symbol.printable}", // {symbol.index}' for symbol in self.symbols]
            )
        }
}};

pub const is_terminal = &[_]bool{{
    {
            "\n    ".join(
                [
                    f"{isinstance(symbol, TerminalSymbol) and 'true' or 'false'},"
                    for symbol in self.symbols
                ]
            )
        }
}};

pub const is_generative_terminal = &[_]bool{{
    {
            "\n    ".join(
                [
                    f"{isinstance(symbol, GenerativeTerminalSymbol) and 'true' or 'false'},"
                    for symbol in self.symbols
                ]
            )
        }
}};

pub const variables = &[_][]const u8{{
    {"\n    ".join([f'"{variable.printable}",' for variable in self.variables])}
}};

pub const symbol_by_variable = &[_]usize{{
    {"\n    ".join([f"{variable.index}," for variable in self.variables])}
}};

pub const rules = &[_]data_structures.Rule{{
{
            "\n".join(
                [
                    f'''\
    data_structures.Rule{{ .header = {
                        VariableSymbol(id=header).variable_index
                    }, .right_hand_side = \
&[_]u16{{{
                        (" " if len(right_hand_side.symbols) > 1 else "")
                        + ", ".join(
                            [f"{symbol.index}" for symbol in right_hand_side.symbols]
                        )
                        + (" " if len(right_hand_side.symbols) > 1 else "")
                    }}}, .right_hand_side_index = "{
                        self.rules[header].index(right_hand_side)
                    }" }}, // {VariableSymbol(id=header).printable}'''
                    for header, right_hand_side in self.rules_list
                ]
            )
        }
}};

pub const rule_procedures = rule_procedures: {{
    var arr: [{len(self.rules_list)}]?*const data_structures.Procedure = .{{null}} ** {
            len(self.rules_list)
        };

    for (rules, 0..) |rule, index| {{
        const procedure_name = "reduction_" ++ variables[rule.header] ++ "_" ++ rule.right_hand_side_index;
        if (@hasDecl(parser.procedures, procedure_name)) {{
            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(parser.procedures, procedure_name), procedure_name);
        }}
    }}

    break :rule_procedures arr;
}};

pub const symbol_procedures = symbol_procedures: {{
    var arr: [{len(self.symbols)}]?*const data_structures.Procedure = .{{null}} ** {
            len(self.symbols)
        };

    for (symbols, 0..) |symbol, index| {{
        const procedure_name = "reduction_" ++ symbol;
        if (@hasDecl(parser.procedures, procedure_name)) {{
            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(parser.procedures, procedure_name), symbol);
        }}
    }}

    break :symbol_procedures arr;
}};

const variable_procedure_names = &[_][]const []const u8{{
    {
            "\n    ".join(
                [
                    f"&[_][] const u8{{{
                        ', '.join(
                            [
                                f'"{procedure.decode("utf-8")}"'
                                for procedure in variable.procedures
                            ]
                        )
                    }}},"
                    for variable in self.variables
                ]
            )
        }
}};

const ProcedureSequenceNode = struct {{
    procedure: *const data_structures.Procedure,
    next: ?*const ProcedureSequenceNode,
}};

pub const variable_procedures = variable_procedures: {{
    var arr: [{len(self.variables)}]?*const ProcedureSequenceNode = .{{null}} ** {
            len(self.variables)
        };

    for (variable_procedure_names, 0..) |procedure_names, index| {{
        var last: ?*const ProcedureSequenceNode = null;
        for (procedure_names) |procedure_name| {{
            last = &ProcedureSequenceNode{{
                .procedure = data_structures.wrap_procedure(data_structures.Procedure, @field(parser.procedures, procedure_name), procedure_name),
                .next = last,
            }};
            arr[index] = last;
        }}
    }}

    break :variable_procedures arr;
}};

pub const reduction_procedure: ?*const data_structures.Procedure = if (@hasDecl(parser.procedures, "reduction")) data_structures.wrap_procedure(data_structures.Procedure, @field(parser.procedures, "reduction"), "reduction") else null;"""
