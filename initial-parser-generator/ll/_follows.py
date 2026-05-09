from pathlib import Path
from typing import override

from data_structures import (
    Rule,
    TerminalSymbol,
    VariableSymbol,
)
from ll._firsts import LLParserGeneratorFirstsMixin


class LLParserGeneratorFollowsMixin(LLParserGeneratorFirstsMixin):
    _follows_cache: dict[VariableSymbol, dict[TerminalSymbol, Rule]]

    def __init__(self) -> None:
        self._follows_cache = {}
        super().__init__()

    @override
    def log_to_file(self, directory: Path) -> None:
        super().log_to_file(directory)
        if directory:
            with (directory / "follows.log").open("w") as output:
                for variable in self.rules:
                    print(variable.decode("utf-8"), file=output)
                    print(
                        "  "
                        + "\n  ".join(
                            [
                                f"{repr(i)}: {j[0].decode('utf-8')} -> {j[1]}"
                                for i, j in sorted(
                                    self._follows(VariableSymbol(id=variable)).items(),
                                    key=lambda i: i[0],
                                )
                            ]
                        ),
                        file=output,
                    )

    def _follows(
        self,
        variable: VariableSymbol,
        *,
        _visited: set[VariableSymbol] = set(),
    ) -> dict[TerminalSymbol, Rule]:
        if variable not in self._follows_cache:
            if variable in _visited:
                return {}
            symbol_follows: dict[TerminalSymbol, Rule] = {}
            for variable_id, right_hand_sides in self.rules.items():
                for right_hand_side in right_hand_sides:
                    try:
                        variable_index = -1
                        length = len(right_hand_side.symbols)
                        while True:
                            variable_index = right_hand_side.symbols.index(
                                variable,
                                variable_index + 1,
                            )
                            for index in range(variable_index + 1, length):
                                rhs_symbol = right_hand_side.symbols[index]
                                if isinstance(rhs_symbol, VariableSymbol):
                                    if rhs_symbol != variable:
                                        symbol_follows |= self._firsts(rhs_symbol)
                                elif isinstance(rhs_symbol, TerminalSymbol):
                                    symbol_follows[rhs_symbol] = (
                                        variable_id,
                                        right_hand_side,
                                    )
                                if rhs_symbol not in self.nullables:
                                    break
                            else:
                                if VariableSymbol(id=variable_id) != variable:
                                    symbol_follows |= self._follows(
                                        VariableSymbol(id=variable_id),
                                        _visited=_visited | {variable},
                                    )

                    except ValueError:
                        pass

            if not _visited:
                self._follows_cache[variable] = symbol_follows
            else:
                return symbol_follows
        return self._follows_cache[variable]
