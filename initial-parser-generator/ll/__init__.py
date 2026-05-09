from data_structures import RightHandSide, VariableSymbol
from ll._zig import LLParserGeneratorZigMixin


class LLParserGenerator(LLParserGeneratorZigMixin):
    parser_type = "ll"

    def from_bytes(self, grammar_text: bytes):
        super().from_bytes(grammar_text)
        self.generative_terminal_id = b"GenerativeTerminal"
        self.rules[self.generative_terminal_id].append(RightHandSide([]))
        self.symbols.append(VariableSymbol(id=self.generative_terminal_id))
