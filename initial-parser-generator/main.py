from __future__ import annotations

import argparse
import tempfile
from pathlib import Path
from typing import Literal, TypedDict, cast

import shtab

from glr import GLRParserGenerator
from ll import LLParserGenerator
from lr import LRParserGenerator

type ParserGenerator = Literal["LL", "LR", "GLR"]

ParserGenerators = TypedDict(
    "ParserGenerators",
    {
        "LL": type[LLParserGenerator],
        "LR": type[LRParserGenerator],
        "GLR": type[GLRParserGenerator],
    },
)

parser_generators: ParserGenerators = {
    "LL": LLParserGenerator,
    "LR": LRParserGenerator,
    "GLR": GLRParserGenerator,
}


def arg_is_language(input: str) -> tuple[dict[str, Path], Path]:
    cwd = Path().absolute()
    language_path = cwd / input
    input_paths = {
        grammar_type: input_path
        for grammar_type in parser_generators.keys()
        if (input_path := language_path / f"{grammar_type.lower()}.grm").exists()
    }
    output_path = language_path / "_parse-table.zig"
    if not input_paths:
        raise argparse.ArgumentTypeError(f'No grammar exists in "{language_path}"')

    try:
        with tempfile.TemporaryFile(dir=language_path):
            pass
    except Exception:
        raise argparse.ArgumentTypeError(f'File "{output_path}" is not writable!')

    return input_paths, output_path


def main():
    parser = argparse.ArgumentParser(description="LL, LR and GLR parser generator.")

    parser.add_argument(
        "--language",
        type=arg_is_language,
        help="The name of the programming language to generate parse table for.",
    )

    log_group = parser.add_mutually_exclusive_group()
    log_group.add_argument(
        "--generate-logs",
        dest="logs_directory",
        action="store_const",
        const=Path("logs"),
        help="If provided, it will output logs for each step.",
    )
    log_group.add_argument(
        "--logs-directory",
        type=Path,
        required=False,
        help="Defaults to ./logs",
    )

    parser.add_argument(
        "--graphs-directory",
        type=Path,
        required=False,
        help="Defaults to ./graphs",
    )
    parser.add_argument(
        "--graph",
        action="store_true",
        help="If provided, it will generate an html graph for the grammar using custom graph engine.",
    )
    parser.add_argument(
        "--graph-interactive",
        action="store_true",
        help="If provided, it will generate an interactive html graph for the grammar using.",
    )
    parser.add_argument(
        "--graphviz",
        action="store_true",
        help="If provided, it will generate an html graph for the grammar using graphviz.",
    )
    parser.add_argument(
        "--graph-visjs",
        action="store_true",
        help="If provided, it will generate an html graph for the grammar using visjs.",
    )
    parser.add_argument(
        "--graphs-dir",
        type=Path,
        default=Path("graphs"),
        help="Defaults to ./graphs",
    )

    shtab.add_argument_to(parser)
    args, _ = parser.parse_known_args()

    grammar_paths, parse_table_path = cast(
        "tuple[dict[str, Path], Path]", args.language
    )

    parser_type_choices = list(parser_generators.keys() & grammar_paths.keys())
    parser.add_argument(
        "--parser-type",
        choices=parser_type_choices,
        default=parser_type_choices[0],
        required=len(parser_type_choices) != 1,
        help="The parser type to use, current supported parsers: LL, LR",
    )

    args, extra_args = parser.parse_known_args()

    parser_generator = parser_generators[args.parser_type]()
    parser_generator.parse_args(extra_args)

    parser_generator.from_bytes(grammar_paths[args.parser_type].open("rb").read())

    if args.graph:
        from generate_graph import generate_graph

        generate_graph(args.graphs_dir, parser_generator.rules)

    if args.graph_interactive:
        from generate_graph_interactive import generate_graph

        generate_graph(args.graphs_dir, parser_generator.rules)

    if args.graph_visjs:
        from generate_graph_visjs import generate_graph

        generate_graph(args.graphs_dir, parser_generator.rules)

    if args.graphviz:
        from generate_graph_graphviz import generate_graph

        generate_graph(args.graphs_dir, parser_generator.rules)

    if args.logs_directory:
        args.logs_directory.mkdir(exist_ok=True, parents=True)
        parser_generator.log_to_file(args.logs_directory)

    with parse_table_path.open("w") as parse_table_file:
        print(
            parser_generator.zig_parser,
            file=parse_table_file,
        )


if __name__ == "__main__":
    main()
