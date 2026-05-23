import json
from collections import defaultdict
from functools import cached_property
from pathlib import Path
from typing import override

from data_structures import (
    RightHandSide,
    Symbol,
    TerminalSymbol,
    VariableSymbol,
)
from ll._firsts import LLParserGeneratorFirstsMixin
from ll._follows import LLParserGeneratorFollowsMixin


class LLParserGeneratorParseTableMixin(
    LLParserGeneratorFollowsMixin, LLParserGeneratorFirstsMixin
):
    @override
    def log_to_file(self, directory: Path) -> None:
        super().log_to_file(directory)
        if directory:
            with (directory / "parse-table.log").open("w") as output:
                print(
                    json.dumps(
                        {
                            variable.id.decode("utf-8"): {
                                repr(i): repr(j) for i, j in row.items()
                            }
                            for variable, row in self.parse_table.items()
                        },
                        indent=2,
                    ),
                    file=output,
                )

    @cached_property
    def parse_table(self) -> dict[Symbol, dict[TerminalSymbol, RightHandSide]]:
        parse_table: dict[Symbol, dict[TerminalSymbol, RightHandSide]] = defaultdict(
            dict
        )
        for symbol in self.symbols:
            if isinstance(symbol, VariableSymbol):
                for terminal, rule in self._firsts(symbol).items():
                    parse_table[symbol][terminal] = rule[1]
                if symbol in self.nullables:
                    for terminal, rule in self._follows(symbol).items():
                        if (
                            terminal in parse_table[symbol]
                            and parse_table[symbol][terminal] != self.nullables[symbol]
                        ):
                            raise SyntaxError(
                                f"""Ambiguity in parse table for nullable variable "{symbol}":
Token "{terminal.id.decode("utf-8")}" shows up both in its firsts as well as its follows:
{symbol},"{terminal.id.decode("utf-8")}": {symbol}->{parse_table[symbol][terminal]}
{symbol},"{terminal.id.decode("utf-8")}": {rule[0].decode("utf-8")}->{rule[1]}"""
                            )
                        parse_table[symbol][terminal] = self.nullables[symbol][1]

        return parse_table
