from data_structures import VariableSymbol
from ll._zig import LLParserGeneratorZigMixin


class LLParserGenerator(LLParserGeneratorZigMixin):
    parser_type = "ll"

    def check_grammar(self) -> None:
        for variable, right_hand_sides in self.rules.items():
            for right_hand_side in right_hand_sides:
                if (
                    right_hand_side.symbols
                    and right_hand_side.symbols[0].id == variable
                ):
                    raise SyntaxError(
                        f'Rule "{repr(VariableSymbol(id=variable))} -> {right_hand_side}" has left-recursion.'
                    )
        super().check_grammar()
