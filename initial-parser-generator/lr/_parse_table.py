from collections import defaultdict
from functools import cached_property

from data_structures import Symbol
from glr._data_structures import (
    AcceptResolution,
    Resolution,
    State,
)
from glr._parse_table import GLRParserGeneratorParseTableMixin


class LRParserGeneratorParseTableMixin(GLRParserGeneratorParseTableMixin):
    @cached_property
    def lr_parse_table(self) -> dict[State, dict[Symbol, Resolution]]:
        glr_parse_table = super().parse_table
        parse_table: dict[State, dict[Symbol, Resolution]] = defaultdict(
            dict,
        )

        for state in glr_parse_table:
            for symbol in glr_parse_table[state]:
                resolutions = glr_parse_table[state][symbol]
                if len(resolutions) > 1:
                    if accept_resolution_list := [
                        resolution
                        for resolution in resolutions
                        if isinstance(resolution, AcceptResolution)
                    ]:
                        parse_table[state][symbol] = accept_resolution_list[0]
                    else:
                        #                     for resolution in resolutions:
                        #                         for item_ in state.items:
                        #                             if (
                        #                                 item_.head_symbol is None
                        #                                 and item_.look_ahead == item.head_symbol
                        #                             ):
                        #                                 q = """
                        # - Shift: {item} ~> {
                        #                                         [
                        #                                             i
                        #                                             for i in resolution.state.items
                        #                                             if i.look_ahead == item.head_symbol
                        #                                         ]
                        #                                     }
                        # - Reduction: {item_} ~> {table[item.head_symbol]}"""
                        raise SyntaxError(
                            f"""Ambiguity in parse table for token "{symbol.printable}" in {state}:
{"\n".join([f"- {resolution}" for resolution in resolutions])}"""
                        )
                else:
                    parse_table[state][symbol] = next(iter(resolutions))

        return parse_table
