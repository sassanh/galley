from __future__ import annotations

import dataclasses
from functools import cached_property

from data_structures import (
    RightHandSide,
    Rule,
    Symbol,
    TerminalSymbol,
    VariableSymbol,
)

tuple_type = tuple


@dataclasses.dataclass(slots=True)
class Item:
    variable: VariableSymbol
    right_hand_side: RightHandSide
    head: int
    look_ahead: TerminalSymbol
    _hash: int = dataclasses.field(init=False)
    head_symbol: Symbol | None = None
    advanced: Item | None = None

    def __post_init__(self):
        self._hash = hash(
            (
                self.head,
                self.look_ahead.id,
                self.variable.id,
                *self.right_hand_side.symbols,
            )
        )

        symbols = self.right_hand_side.symbols
        if self.head < len(symbols):
            self.head_symbol = symbols[self.head]
            self.advanced = Item(
                self.variable, self.right_hand_side, self.head + 1, self.look_ahead
            )

    def __hash__(self) -> int:
        return self._hash

    @property
    def remaining(self) -> list["Symbol"]:
        return self.right_hand_side.symbols[self.head + 1 :]

    def __lt__(self, other: "Item") -> bool:
        return self._hash < other._hash


@dataclasses.dataclass(slots=True)
class State:
    items: frozenset[Item]
    _hash: int = dataclasses.field(init=False)
    items_by_symbol: dict[int, State] = dataclasses.field(init=False)

    def __post_init__(self):
        self._hash = hash(self.items)

        index: dict[int, list[Item]] = {}

        for item in self.items:
            head_symbol = item.head_symbol
            if head_symbol is not None:
                if head_symbol.index not in index:
                    index[head_symbol.index] = []
                if item.advanced:
                    index[head_symbol.index].append(item.advanced)

        self.items_by_symbol = {
            symbol: State(frozenset(itms)) for symbol, itms in index.items()
        }

    def __hash__(self) -> int:
        return self._hash

    def __eq__(self, other) -> bool:
        return self._hash == other._hash

    def __lt__(self, other: "State") -> bool:
        return self._hash < other._hash


empty_state = State(items=frozenset())


@dataclasses.dataclass(frozen=True)
class Resolution:
    @cached_property
    def type_string(self) -> str:
        symbol_type = type(self).__name__
        assert symbol_type.endswith("Resolution")
        return symbol_type[: -len("Resolution")].lower()


@dataclasses.dataclass(frozen=True)
class ShiftResolution(Resolution):
    state: State

    def __repr__(self) -> str:
        return f"[Shift:{self.state}]"


@dataclasses.dataclass(frozen=True)
class ReduceResolution(Resolution):
    rule: Rule

    def __repr__(self) -> str:
        return f"[Reduce:{self.rule[0].decode('utf-8')} <~ {self.rule[1]}]"


@dataclasses.dataclass(frozen=True)
class GotoResolution(Resolution):
    state: State

    def __repr__(self) -> str:
        return f"[Goto:{self.state}]"


@dataclasses.dataclass(frozen=True)
class AcceptResolution(Resolution):
    def __repr__(self) -> str:
        return "[Accept]"
