const std = @import("std");
const ProcedureArguments = @import("galley").data_structures.ProcedureArguments;
const ASTNode = @import("galley").data_structures.ASTNode;
const string_utilities = @import("galley").string_utilities;
const parse_table = @import("galley").parse_table;

const control_characters_uppper_bound = 4;

pub const indentation_syntax = true;
pub const Payload = struct {
    rules: usize = 0,
    fields: usize = 0,
    outcomes: usize = 0,
    indent: usize = 0,
    parse_id: usize = 0,
};

var indent: u16 = 0;

const block_start_id = 1;
const block_end_id = 2;

pub fn reduction(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        var node = args.context.node_allocator.at(node_address);
        var block_start: ?ASTNode.Pointer = null;
        while (if (node.first_child != ASTNode.invalid_pointer and
            args.context.node_allocator.at(node.first_child).payload.parse_id == block_start_id)
            node.first_child
        else
            null) |child_address|
        {
            // We need last BlockStart which is the last when iterating from
            // start of the array and has most indentation
            block_start = try ASTNode.remove_self(child_address, args.context);
        }
        if (block_start) |to_prepend| {
            try ASTNode.insert_before(node_address, args.context, to_prepend);
        }

        var block_end: ?ASTNode.Pointer = null;
        while (if (node.last_child != ASTNode.invalid_pointer and
            args.context.node_allocator.at(node.last_child).payload.parse_id == block_end_id)
            node.last_child
        else
            null) |child_address|
        {
            const new_block_end = try ASTNode.remove_self(child_address, args.context);
            // We need last BlockEnd which is the first when iterating from
            // the end of the array and has least indenation
            if (block_end == null) {
                block_end = new_block_end;
            }
        }
        if (block_end) |to_append| {
            try ASTNode.insert_after(node_address, args.context, to_append);
        }

        var iterator = ASTNode.iterate_augmented(node.first_child, args.context);
        while (iterator.next()) |child_address| {
            const child = args.context.node_allocator.at(child_address);
            node.payload.rules += child.payload.rules;
            node.payload.fields += child.payload.fields;
            node.payload.outcomes += child.payload.outcomes;
        }
    }
}

fn summerize(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        _ = try ASTNode.clean_children(node_address, args.context);
        // node.label = try std.fmt.allocPrint(args.allocator, "{s} ('{s}')", .{
        //     node.label,
        //     node.text,
        // });
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

fn to_character(character: u8, ignore_empty: bool) type {
    _ = character;
    return struct {
        fn function(args: *ProcedureArguments) !void {
            if (args.node) |node_address| {
                _ = try ASTNode.clean_children(node_address, args.context);
                const node = args.context.node_allocator.at(node_address);
                if (ignore_empty) {
                    if (node.first_child == 0) {
                        args.node = null;
                        return;
                    }
                }
                // const spaces = try args.allocator.alloc(u8, if (character == '\n') indent * 2 + 1 else 1);
                // @memset(spaces, ' ');
                // spaces[0] = character;
                // node.text = spaces;
            }
        }
    };
}

pub const reduction_OptionalBlankAndNewLine = to_character(' ', false).function;
pub const reduction_OptionalNewLineMany = to_character('\n', false).function;
pub const reduction_ForceNewLineMany = to_character('\n', false).function;
pub const reduction_new_line = to_character('\n', false).function;

pub fn drop_children(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        _ = try ASTNode.clean_children(node_address, args.context);
    }
}

pub const reduction_PositiveIntegerNumber = drop_children;
pub const reduction_NegativeIntegerNumber = drop_children;
pub const reduction_IntegerNumber = drop_children;
pub const reduction_Number = drop_children;
pub const reduction_text = drop_children;

fn block_edge(parse_id: comptime_int) type {
    return struct {
        fn function(args: *ProcedureArguments) !void {
            if (args.node) |node_address| {
                const node = args.context.node_allocator.at(node_address);
                if (parse_id == block_start_id) indent += 1 else indent -= 1;

                // const spaces = try args.allocator.alloc(u8, indent * 2 + 1);
                // @memset(spaces, ' ');
                // spaces[0] = '\n';
                // args.node.?.text = spaces;
                // args.node.?.label = if (parse_id == block_start_id) "BlockStart" else "BlockEnd";

                node.payload.parse_id = parse_id;
            }
        }
    };
}

pub const reduction_block_start = block_edge(block_start_id).function;
pub const reduction_block_end = block_edge(block_end_id).function;

pub fn replace_with_children(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        const removed_children = try ASTNode.clean_children(node_address, args.context);
        if (removed_children.len > 0)
            args.node = removed_children[0]
        else
            args.node = null;
    }
}

pub const reduction_Operand = replace_with_children;
pub const reduction_Expression_1 = replace_with_children;
pub const reduction_OperandAndNumber = replace_with_children;
pub const reduction_ActionBody = replace_with_children;

pub fn reduction_ActionOutcomeEntry(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        const removed_address = try ASTNode.remove_child(node_address, args.context, 0);
        args.context.node_allocator.at(removed_address).payload.outcomes = 1;
        args.node = removed_address;
    }
}

pub fn reduction_FieldRow(args: *ProcedureArguments) void {
    if (args.node) |node_address| {
        const node = args.context.node_allocator.at(node_address);
        node.payload.fields = 1;
    }
}

pub fn right_recursive_reduction(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        const node = args.context.node_allocator.at(node_address);
        if (node.first_child != ASTNode.invalid_pointer) {
            try reduction(args);
            const removing_address = (try ASTNode.remove(node.last_child, args.context, 1))[0];
            // const removing_node = try ASTNode.remove_child(
            //     node_address,
            //     args.context,
            //     data_structures.ASTNode.augmented_length(node_address, args.context.node_allocator) - 1,
            // );
            if (args.context.node_allocator.at(removing_address).first_child != ASTNode.invalid_pointer) {
                try ASTNode.append_children(
                    node_address,
                    args.context,
                    (try ASTNode.clean_children(removing_address, args.context))[0],
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
    if (args.node) |node_address| {
        const node = args.context.node_allocator.at(node_address);
        if (args.context.verbosity > 0) {
            std.debug.print("{f}({d}) -> |", .{
                string_utilities.fmtString(
                    if (args.rule.?.header == -1)
                        "-1"
                    else
                        parse_table.variables[args.rule.?.header],
                ),
                args.rule.?.header,
            });
            for (args.rule.?.right_hand_side) |idx| {
                std.debug.print("{f}({d})|", .{
                    string_utilities.fmtString(if (idx == -1)
                        "-1"
                    else
                        parse_table.symbols[idx]),
                    idx,
                });
            }
            std.debug.print("\n", .{});
        }

        // args.node.?.label = try std.fmt.allocPrint(args.allocator, "{s} '{s}'", .{
        //     args.node.?.label,
        //     args.node.?.children[0].text,
        // });

        node.payload.rules = 1;
    }
}

pub fn reduction_Start(args: *ProcedureArguments) !void {
    if (if (args.context.verbosity > 0) args.node else null) |node_address| {
        std.debug.print("\nProgram text:\n{s}\n", .{try ASTNode.augmented_text(node_address, args.context)});
    }

    const log_file = try std.Io.Dir.cwd().createFile(args.context.io, "sanbus-parse.log", .{
        .lock = .exclusive,
    });
    defer log_file.close(args.context.io);

    var buffer: [4096]u8 = undefined;
    var buffered_writer: std.Io.File.Writer = .init(log_file, args.context.io, &buffer);
    const writer = &buffered_writer.interface;

    if (args.node) |node_address| {
        const node = args.context.node_allocator.at(node_address);
        const child = args.context.node_allocator.at(node.first_child);
        try writer.print("{d} rules, {d} fields, {d} outcomes!\n\n{f}\n", .{
            child.payload.rules,
            child.payload.fields,
            child.payload.outcomes,
            string_utilities.fmtASTNode(node_address, args.context),
        });
    }

    try writer.flush();
}

pub fn drop_if_empty(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        const node = args.context.node_allocator.at(node_address);
        if (node.first_child == ASTNode.invalid_pointer) {
            // std.debug.print("drop from '{s}'\n", .{args.node.?.label});
            args.node = null;
        }
    }
}
