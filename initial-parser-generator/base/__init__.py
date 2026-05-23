import abc
import argparse
import re
from collections import defaultdict
from functools import cached_property, reduce
from pathlib import Path
from typing import Sequence, cast

from data_structures import (
    EndSymbol,
    RightHandSide,
    Rule,
    Symbol,
    VariableSymbol,
)


class ParserGeneratorBaseMixin(abc.ABC):
    rules: dict[bytes, list[RightHandSide]]
    symbols: list[Symbol]
    start_variable: VariableSymbol

    @property
    @abc.abstractmethod
    def parser_type(self) -> str:
        raise NotImplementedError

    def __init__(self) -> None:
        self.rules = defaultdict(list)
        self.symbols = []

    @cached_property
    def arguments_parser(self) -> argparse.ArgumentParser:
        parser = argparse.ArgumentParser()
        return parser

    def parse_args(self, argument_strings: Sequence[str] | None) -> None:
        args = self.arguments_parser.parse_args(argument_strings)

        for arg, value in args._get_kwargs():
            setattr(self, arg, value)

    def patch_grammar(self) -> None:
        pass

    def from_bytes(self, grammar_text: bytes):
        header_symbol: VariableSymbol | None = None
        grammar_start_variable: VariableSymbol | None = None

        for line_number, line_ in enumerate(grammar_text.split(b"\n")):
            line = line_.rstrip()

            if line == b"" or line.lstrip().startswith(b"#"):
                continue

            line = line.replace(b"\r", b"\n")

            if header_symbol is not None and line.startswith(b" "):
                try:
                    rule_procedures, _, line = line[1:].partition(b"|")
                    literals = []
                    items = (
                        re.sub(
                            b"'([^]*)",
                            lambda a: literals.append(a.group(1)) or b"\x00",
                            line,
                        ).split(b" ")
                        if line
                        else []
                    )
                    items = [
                        re.sub(b"\x00", lambda _: b'"' + literals.pop(0) + b'"', item)
                        for item in items
                    ]
                    items = [
                        item.decode("unicode-escape").encode("raw-unicode-escape")
                        for item in items
                    ]

                    right_hand_side = RightHandSide(
                        symbols=tuple(Symbol.from_str(i) for i in items),
                        procedures=list(reversed(rule_procedures[1:].split(b"@"))),
                    )
                except ValueError as exception:
                    raise ValueError(
                        f"While parsing line {line_number + 1}\n{line.decode('utf-8')}\n{exception}"
                    )
                for symbol in right_hand_side.symbols:
                    if symbol not in self.symbols:
                        self.symbols.append(symbol)
                self.rules[header_symbol.id].append(right_hand_side)
            else:
                symbol = Symbol.from_str(line)
                if not isinstance(symbol, VariableSymbol):
                    raise ValueError("Rule headers can only be variables")
                header_symbol = symbol
                if header_symbol not in self.symbols:
                    self.symbols.append(header_symbol)
                grammar_start_variable = grammar_start_variable or header_symbol

        self.start_variable = VariableSymbol(id=b"AugmentedStart")
        self.symbols.append(self.start_variable)
        self.symbols.append(EndSymbol())

        if grammar_start_variable is None:
            raise SyntaxError("A grammar should have at least one rule!")

        self.rules[self.start_variable.id] = [
            RightHandSide(symbols=(grammar_start_variable, EndSymbol()))
        ]

        self.patch_grammar()
        self.check_grammar()

    def check_grammar(self) -> None:
        for variable in self.variables:
            if variable.id not in self.rules:
                raise SyntaxError(f'There is no rule for variable "{variable}"!')
        del self.variables

    def log_to_file(self, directory: Path) -> None:
        with (directory / "symbols.log").open("w") as output:
            for symbol in self.symbols:
                print(
                    f"{symbol.index}.", repr(symbol), type(symbol).__name__, file=output
                )

        with (directory / "rules.log").open("w") as output:
            for index, rule in enumerate(self.rules_list):
                print(f"{index}.", rule[0].decode("utf-8"), "->", rule[1], file=output)

    @cached_property
    def variables(self) -> list[VariableSymbol]:
        return sorted(
            symbol for symbol in self.symbols if isinstance(symbol, VariableSymbol)
        )

    @cached_property
    def rules_list(self) -> list[Rule]:
        return sorted(
            reduce(
                lambda a, b: a + [(b[0], right_hand_side) for right_hand_side in b[1]],
                self.rules.items(),
                cast("list[Rule]", []),
            )
        )

    @cached_property
    def right_hand_sides(self) -> list[RightHandSide]:
        return sorted(
            reduce(
                lambda a, b: a | b,
                self.rules.values(),
                cast("set[RightHandSide]", set()),
            )
        )
