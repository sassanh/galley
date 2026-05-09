import json
from collections import defaultdict
from functools import cached_property
from pathlib import Path
from typing import override

from data_structures import (
    EndSymbol,
    Symbol,
    TerminalSymbol,
)
from glr._data_structures import (
    AcceptResolution,
    GotoResolution,
    ReduceResolution,
    Resolution,
    ShiftResolution,
    State,
    empty_state,
)
from glr._goto import GLRParserGeneratorGotoMixin


class GLRParserGeneratorParseTableMixin(GLRParserGeneratorGotoMixin):
    def _parse_table_result_repr(self, result: Resolution) -> str:
        match result:
            case ShiftResolution(state=state):
                return f"s{self.canonical_state_indices[state]}"

            case ReduceResolution(rule):
                return f"r{self.rules_list.index(rule)}"

            case GotoResolution(state=state):
                return repr(self.canonical_state_indices[state])

            case AcceptResolution():
                return "Accept"
        raise ValueError

    @override
    def log_to_file(self, directory: Path) -> None:
        super().log_to_file(directory)
        if directory:
            with (directory / "parse-table.log").open("w") as output:
                print(
                    json.dumps(
                        {
                            f"{self.canonical_state_indices[state]}:{state}": {
                                symbol.id.decode(): "\n".join(
                                    f"{self._parse_table_result_repr(parse_table_result)}:{parse_table_result}"
                                    for parse_table_result in parse_table_results
                                )
                                for symbol, parse_table_results in row.items()
                            }
                            for state, row in self.parse_table.items()
                        },
                        indent=2,
                        sort_keys=True,
                    ),
                    file=output,
                )

    @cached_property
    def parse_table(self) -> dict[State, dict[Symbol, set[Resolution]]]:
        parse_table: dict[State, dict[Symbol, set[Resolution]]] = defaultdict(
            lambda: defaultdict(set)
        )

        def report_progress(progress: int):
            print(
                f"Parse table generation progress: {progress}/{len(self.canonical_states)}"
            )

        for state in self.canonical_states:
            table = parse_table[state]
            if (index := self.canonical_state_indices[state]) % 50 == 0:
                report_progress(index)
            for item in state.items:
                if item.variable == self.start_variable:
                    table[EndSymbol()].add(AcceptResolution())
                elif isinstance(item.head_symbol, TerminalSymbol):
                    table[item.head_symbol].add(
                        ShiftResolution(state=self._goto(state, item.head_symbol))
                    )
                elif item.head_symbol is None:
                    table[item.look_ahead].add(
                        ReduceResolution(rule=(item.variable.id, item.right_hand_side))
                    )

            for variable in self.variables:
                goto_state = self._goto(state, variable)
                if goto_state != empty_state:
                    resolution = GotoResolution(goto_state)
                    table[variable].add(resolution)

        report_progress(len(self.canonical_states))

        return parse_table
