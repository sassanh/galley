from pathlib import Path
from typing import override

from base._nullables import ParserGeneratorNullablesMixin
from data_structures import (
    Rule,
    TerminalSymbol,
    VariableSymbol,
)


class LLParserGeneratorFirstsMixin(ParserGeneratorNullablesMixin):
    _firsts_cache: dict[VariableSymbol, dict[TerminalSymbol, Rule]]

    def __init__(self) -> None:
        self._firsts_cache = {}
        super().__init__()

    @override
    def log_to_file(self, directory: Path) -> None:
        super().log_to_file(directory)
        with (directory / "firsts.log").open("w") as output:
            for variable in self.rules:
                print(variable.decode("utf-8"), file=output)
                print(
                    "  "
                    + "\n  ".join(
                        [
                            f"{repr(i)}: {j[0].decode('utf-8')} -> {j[1]}"
                            for i, j in sorted(
                                self._firsts(VariableSymbol(id=variable)).items(),
                                key=lambda i: i[0],
                            )
                        ]
                    ),
                    file=output,
                )

    def _firsts(
        self,
        variable: VariableSymbol,
        *,
        _visited: set[VariableSymbol] | None = None,
    ) -> dict[TerminalSymbol, Rule]:
        if variable not in self._firsts_cache:
            if _visited and variable in _visited:
                return {}
            new_visited = (_visited | {variable}) if _visited else set()
            symbol_firsts: dict[TerminalSymbol, Rule] = {}
            for right_hand_side in self.rules[variable.id]:
                for rhs_symbol in right_hand_side.symbols:
                    if isinstance(rhs_symbol, VariableSymbol):
                        new_firsts = self._firsts(
                            rhs_symbol,
                            _visited=new_visited,
                        )
                        ambiguity_set: set[TerminalSymbol] = {
                            terminal
                            for terminal in symbol_firsts
                            if terminal in new_firsts
                            and right_hand_side != symbol_firsts[terminal]
                        }
                        if ambiguity_set:
                            ambiguity = ambiguity_set.pop()
                            raise SyntaxError(
                                f"""Ambiguity in firsts for variable "{variable}":
{variable},"{repr(ambiguity)}": {variable}->{symbol_firsts[ambiguity][1]}
{variable},"{repr(ambiguity)}": {rhs_symbol}->{new_firsts[ambiguity][1]}"""
                            )
                        symbol_firsts |= {
                            (i, (variable.id, right_hand_side)) for i in new_firsts
                        }

                    elif isinstance(rhs_symbol, TerminalSymbol):
                        symbol_firsts[rhs_symbol] = (variable.id, right_hand_side)

                    if rhs_symbol not in self.nullables:
                        break
            if _visited is None:
                self._firsts_cache[variable] = symbol_firsts
            else:
                return symbol_firsts
        return self._firsts_cache[variable]
