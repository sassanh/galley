from collections import defaultdict

from data_structures import RightHandSide, TerminalSymbol, VariableSymbol
from glr._data_structures import Item, State
from glr._firsts import GLRParserGeneratorFirstsMixin


class GLRParserGeneratorClosureMixin(GLRParserGeneratorFirstsMixin):
    _closure_cache: dict[State, State]

    def __init__(self) -> None:
        self._closure_cache = {}
        super().__init__()

    # @override
    # def log_to_file(self, directory: Path) -> None:
    #     super().log_to_file(directory)
    # with (directory / "closure.log").open("w") as output:
    #     for variable in self.rules:
    #         print(variable.decode("utf-8"), file=output)
    # print(
    #     "  "
    #     + "\n  ".join(
    #         [
    #             f'"{i.decode("utf-8")}"'
    #             for i in sorted(
    #                 self._closure(VariableSymbol(variable)),
    #             )
    #         ]
    #     ),
    #     file=output,
    # )

    def _closure(self, state: State) -> State:
        if state in self._closure_cache:
            return self._closure_cache[state]

        closure: dict[RightHandSide, dict[bytes, dict[bytes, set[int]]]] = defaultdict(
            lambda: defaultdict(lambda: defaultdict(set))
        )
        c = set(state.items)

        for i in state.items:
            closure[i.right_hand_side][i.variable.id][i.look_ahead.id].add(i.head)
        to_check_items = list(state.items)

        while to_check_items:
            item = to_check_items.pop()

            head_symbol = item.head_symbol
            if not isinstance(head_symbol, VariableSymbol):
                continue

            rules = self.rules.get(head_symbol.id, [])
            context = [*item.remaining, item.look_ahead]
            firsts = self._firsts(context)

            for rhs in rules:
                for first in firsts:
                    if 0 not in closure[rhs][head_symbol.id][first.id]:
                        new_item = Item(
                            variable=head_symbol,
                            right_hand_side=rhs,
                            head=0,
                            look_ahead=first,
                        )
                        closure[rhs][head_symbol.id][first.id].add(0)
                        c.add(new_item)
                        to_check_items.append(new_item)

        new_state = State(items=frozenset(c))
        self._closure_cache[state] = new_state
        return new_state
