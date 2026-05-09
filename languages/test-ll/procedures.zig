const std = @import("std");
const ProcedureArguments = @import("root").data_structures.ProcedureArguments;
const string_utilities = @import("root").string_utilities;
const data_structures = @import("root").data_structures;
const parser = @import("parser");

const control_characters_uppper_bound = 4;

pub const Payload = struct {
    rules: u16 = 0,
    fields: u16 = 0,
    outcomes: u16 = 0,
    indent: u16 = 0,
    parse_id: u8 = 0,
};

var indent: u16 = 0;

const block_start_id = 1;
const block_end_id = 2;

pub fn reduction(args: *ProcedureArguments) !void {
    if (args.node) |node| {
        var block_start: ?*data_structures.ASTNode = null;
        while (if (node.children.len > 0 and node.children[0].payload.parse_id == block_start_id)
            node.children[0]
        else
            null) |child|
        {
            // We need last BlockStart which is the last when iterating from
            // start of the array and has most indentation
            block_start = try child.remove_self(args.allocator);
        }
        if (block_start) |to_prepend| {
            try node.insert_before(args.allocator, to_prepend);
        }

        var block_end: ?*data_structures.ASTNode = null;
        while (if (node.children.len > 0 and node.children[node.children.len - 1].payload.parse_id == block_end_id)
            node.children[node.children.len - 1]
        else
            null) |child|
        {
            const new_block_end = try child.remove_self(args.allocator);
            // We need last BlockEnd which is the first when iterating from
            // the end of the array and has least indenation
            if (block_end) |_| {} else {
                block_end = new_block_end;
            }
        }
        if (block_end) |to_append| {
            try node.insert_after(args.allocator, to_append);
        }

        for (node.children) |child| {
            node.payload.rules += child.payload.rules;
            node.payload.fields += child.payload.fields;
            node.payload.outcomes += child.payload.outcomes;
        }
    }
}

fn summerize(args: *ProcedureArguments) !void {
    if (args.node) |node| {
        _ = try node.clean_children(args.allocator);
        node.label = try std.fmt.allocPrint(args.allocator, "{s} ('{s}')", .{
            node.label,
            node.text,
        });
    }
}

pub const reduction_UppercaseId = summerize;
pub const reduction_LowercaseId = summerize;
pub const reduction_Id = summerize;
pub const reduction_Operator = summerize;
pub const reduction_String = summerize;

pub fn drop_self(args: *ProcedureArguments) void {
    args.node = null;
}

pub const reduction_OptionalTypeArray_1 = drop_self;
pub const reduction_OptionalBlank = drop_self;

pub fn reduction_Space(args: *ProcedureArguments) !void {
    _ = try args.node.?.clean_children(args.allocator);
}

fn to_character(character: u8, ignore_empty: bool) type {
    return struct {
        fn function(args: *ProcedureArguments) !void {
            if (args.node) |node| {
                _ = try node.clean_children(args.allocator);
                if (ignore_empty) {
                    if (node.children.len == 0) {
                        args.node = null;
                        return;
                    }
                }
                const spaces = try args.allocator.alloc(u8, if (character == '\n') indent * 2 + 1 else 1);
                @memset(spaces, ' ');
                spaces[0] = character;
                node.text = spaces;
            }
        }
    };
}

pub const reduction_OptionalBlankAndNewLine = to_character(' ', false).function;
pub const reduction_OptionalNewLineMany = to_character('\n', false).function;
pub const reduction_ForceNewLineMany = to_character('\n', false).function;
pub const reduction_new_line = to_character('\n', false).function;

pub fn drop_children(args: *ProcedureArguments) !void {
    _ = try args.node.?.clean_children(args.allocator);
}

pub const reduction_PositiveIntegerNumber = drop_children;
pub const reduction_NegativeIntegerNumber = drop_children;
pub const reduction_IntegerNumber = drop_children;
pub const reduction_Number = drop_children;
pub const reduction_text = drop_children;

fn block_edge(parse_id: comptime_int) type {
    return struct {
        fn function(args: *ProcedureArguments) !void {
            if (parse_id == block_start_id) indent += 1 else indent -= 1;

            const spaces = try args.allocator.alloc(u8, indent * 2 + 1);
            @memset(spaces, ' ');
            spaces[0] = '\n';
            args.node.?.text = spaces;
            args.node.?.label = if (parse_id == block_start_id) "BlockStart" else "BlockEnd";

            args.node.?.payload.parse_id = parse_id;
        }
    };
}

pub const reduction_block_start = block_edge(block_start_id).function;
pub const reduction_block_end = block_edge(block_end_id).function;

pub fn replace_with_children(args: *ProcedureArguments) !void {
    if (args.node) |node| {
        const removed_children = try node.clean_children(args.allocator);
        if (removed_children.len > 0) args.node = removed_children[0] else args.node = null;
    }
}

pub const reduction_Operand = replace_with_children;
pub const reduction_Expression_1 = replace_with_children;
pub const reduction_OperandAndNumber = replace_with_children;
pub const reduction_ActionBody = replace_with_children;

pub fn reduction_ActionOutcomeEntry(args: *ProcedureArguments) !void {
    args.node = (try args.node.?.remove_child(args.allocator, 0));
    args.node.?.payload.outcomes = 1;
}

pub fn reduction_FieldRow(args: *ProcedureArguments) void {
    args.node.?.payload.fields = 1;
}

pub fn right_recursive_reduction(args: *ProcedureArguments) !void {
    if (args.node) |node| {
        if (node.children.len > 1) {
            try reduction(args);
            const removing_node = try node.remove_child(args.allocator, node.children.len - 1);
            if (removing_node.children.len > 0) {
                try node.append_children(
                    args.allocator,
                    (try removing_node.clean_children(args.allocator))[0],
                );
            }
        }
    }
}

pub const reduction_RulesTail_0 = right_recursive_reduction;
pub const reduction_Fields_0 = right_recursive_reduction;
pub const reduction_ActionOutcome_0 = right_recursive_reduction;
pub const reduction_ActionsToDispatch_0 = right_recursive_reduction;
pub const reduction_SideEffectsToDispatch_0 = right_recursive_reduction;
pub const reduction_InstantiationParameters_0 = right_recursive_reduction;
pub const reduction_Parameters_0 = right_recursive_reduction;

pub fn drop_first_child(args: *ProcedureArguments) !void {
    // Let's keep "- "
    _ = args;
    // _ = try args.node.?.remove_children(args.allocator, 0, 2);
}

pub const reduction_ActionsToDispatch_1 = drop_first_child;
pub const reduction_SideEffectsToDispatch_1 = drop_first_child;

pub fn reduction_Rule(args: *ProcedureArguments) !void {
    if (args.verbosity > 0) {
        std.debug.print("{f}({d}) -> |", .{
            string_utilities.fmtString(
                if (args.rule.?.header == -1)
                    "-1"
                else
                    parser.parse_table.variables[args.rule.?.header],
            ),
            args.rule.?.header,
        });
        for (args.rule.?.right_hand_side) |idx| {
            std.debug.print("{f}({d})|", .{
                string_utilities.fmtString(if (idx == -1)
                    "-1"
                else
                    parser.parse_table.symbols[idx]),
                idx,
            });
        }
        std.debug.print("\n", .{});
    }

    args.node.?.label = try std.fmt.allocPrint(args.allocator, "{s} '{s}'", .{
        args.node.?.label,
        args.node.?.children[0].*.text,
    });

    args.node.?.payload.rules = 1;
}

pub fn reduction_Start(args: *ProcedureArguments) !void {
    if (if (args.verbosity > 0) args.node else null) |node| {
        std.debug.print("\nProgram text:\n{s}\n", .{try node.augmented_text(args.allocator)});
    }

    const log_file = try std.Io.Dir.cwd().createFile(args.io, "sanbus-parse.log", .{
        .lock = .exclusive,
    });
    defer log_file.close(args.io);

    var buffer: [4096]u8 = undefined;
    var buffered_writer: std.Io.File.Writer = .init(log_file, args.io, &buffer);
    const writer = &buffered_writer.interface;

    try writer.print("{d} rules, {d} fields, {d} outcomes!\n\n{f}\n", .{
        args.node.?.children[0].payload.rules,
        args.node.?.children[0].payload.fields,
        args.node.?.children[0].payload.outcomes,
        string_utilities.fmtASTNode(args.node),
    });

    try writer.flush();
}

pub fn drop_if_empty(args: *ProcedureArguments) !void {
    if (args.node) |node| {
        if (node.children.len == 0) {
            // std.debug.print("drop from '{s}'\n", .{args.node.?.label});
            args.node = null;
        }
    }
}
