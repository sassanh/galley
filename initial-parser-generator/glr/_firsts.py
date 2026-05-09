from pathlib import Path
from typing import Sequence, TypeGuard, overload, override

from base._nullables import ParserGeneratorNullablesMixin
from data_structures import (
    SpecialSymbol,
    Symbol,
    TerminalSymbol,
    VariableSymbol,
)


def _is_sequence_of_symbols(x: object) -> TypeGuard[Sequence[Symbol]]:
    return isinstance(x, list)


class GLRParserGeneratorFirstsMixin(ParserGeneratorNullablesMixin):
    _firsts_cache: dict[VariableSymbol, set[TerminalSymbol]]

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
                            repr(i)
                            for i in sorted(
                                self._firsts(VariableSymbol(id=variable)),
                            )
                        ]
                    ),
                    file=output,
                )

    @overload
    def _firsts(
        self,
        variable: VariableSymbol,
        *,
        _visited: set[VariableSymbol] = set(),
    ) -> set[TerminalSymbol]: ...
    @overload
    def _firsts(
        self,
        symbols: Sequence[Symbol],
        *,
        _visited: set[VariableSymbol] = set(),
    ) -> set[TerminalSymbol]: ...
    def _firsts(
        self,
        item: VariableSymbol | Sequence[Symbol],
        *,
        _visited: set[VariableSymbol] = set(),
    ) -> set[TerminalSymbol]:
        symbol_firsts: set[TerminalSymbol] = set()
        if _is_sequence_of_symbols(item):
            symbols = item
            for symbol in symbols:
                if isinstance(symbol, TerminalSymbol):
                    symbol_firsts.add(symbol)
                    break
                if isinstance(symbol, VariableSymbol):
                    symbol_firsts |= self._firsts(symbol)
                    if symbol not in self.nullables:
                        break
            return symbol_firsts

        if not isinstance(item, VariableSymbol):
            return symbol_firsts

        variable = item

        if variable not in self._firsts_cache:
            if isinstance(variable, SpecialSymbol):
                return symbol_firsts
            if variable in _visited:
                return symbol_firsts
            for right_hand_side in self.rules[variable.id]:
                for rhs_symbol in right_hand_side.symbols:
                    if (
                        isinstance(rhs_symbol, VariableSymbol)
                        and rhs_symbol != variable
                    ):
                        symbol_firsts |= self._firsts(
                            rhs_symbol, _visited=_visited | {variable}
                        )

                    if isinstance(rhs_symbol, TerminalSymbol):
                        symbol_firsts.add(rhs_symbol)

                    if rhs_symbol not in self.nullables:
                        break
            self._firsts_cache[variable] = symbol_firsts
        return self._firsts_cache[variable]
