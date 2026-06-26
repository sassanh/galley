const std = @import("std");
const parse_table = @import("root").parse_table;
const ASTNode = @import("root").data_structures.ASTNode;
const Context = @import("root").data_structures.Context;

const StringSliceFormatter = struct {
    slice: []const []const u8,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void {
        try writer.writeAll("{ \"");
        for (self.slice, 0..) |str, i| {
            if (i > 0) try writer.writeAll("\", \"");
            try std.zig.stringEscape(str, writer);
        }
        try writer.writeAll("\" }");
    }
};

pub fn fmtStringSlice(slice: []const []const u8) StringSliceFormatter {
    return .{ .slice = slice };
}

const StringFormatter = struct {
    string: []const u8,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void {
        try std.zig.stringEscape(self.string, writer);
    }
};

pub fn fmtString(string: []const u8) StringFormatter {
    return .{ .string = string };
}

const ASTNodeFormatter = struct {
    ast_node_address: ?ASTNode.Pointer,
    context: *Context,
    indentation: usize = 0,
    indent_status: []bool = &[0]bool{},

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void {
        for (self.indent_status, 0..) |is_ended, index| {
            if (is_ended) {
                try writer.writeAll(if (index == self.indentation - 1) " ╰" else "  ");
            } else {
                try writer.writeAll(if (index == self.indentation - 1) " ├" else " │");
            }
        }

        if (self.ast_node_address) |ast_node_address| {
            const ast_node = self.context.node_allocator.at(ast_node_address);
            try writer.print(" {s} \"{f}\" ({d})\n", .{
                if (ast_node.variable == std.math.maxInt(u16))
                    "-"
                else
                    parse_table.variables[ast_node.variable],
                fmtString(self.context.get_text_slice(ast_node.text_start, ast_node.text_length)),
                if (ast_node.first_child == ASTNode.invalid_pointer)
                    0
                else
                    ASTNode.augmented_length(ast_node.first_child, self.context.node_allocator),
            });

            var child_indent_status: [256]bool = undefined;
            @memcpy(child_indent_status[0..self.indentation], self.indent_status);
            child_indent_status[self.indentation] = false;

            var iterator = ASTNode.iterate_augmented(ast_node.first_child, self.context);
            while (iterator.next()) |node_address| {
                const node = self.context.node_allocator.at(node_address);
                if (node.next == ASTNode.invalid_pointer) {
                    child_indent_status[self.indentation] = true;
                }
                const f = ASTNodeFormatter{
                    .ast_node_address = node_address,
                    .context = self.context,
                    .indentation = self.indentation + 1,
                    .indent_status = child_indent_status[0 .. self.indentation + 1],
                };
                try f.format(writer);
            }
        } else {
            try writer.print("NULL\n", .{});
            return;
        }
    }
};

pub fn fmtASTNode(ast_node_address: ?ASTNode.Pointer, context: *Context) ASTNodeFormatter {
    return .{
        .ast_node_address = ast_node_address,
        .context = context,
    };
}

pub fn formatWithThousands(value: anytype, buf: []u8) ![]u8 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    const n: u64 = switch (info) {
        .int, .comptime_int => @intCast(value),
        .float, .comptime_float => @intFromFloat(value),
        else => @compileError("formatWithThousands: expected int or float, got " ++ @typeName(T)),
    };

    var tmp: [32]u8 = undefined;
    const digits = std.fmt.bufPrint(&tmp, "{d}", .{n}) catch unreachable;

    var out_pos: usize = 0;
    const len = digits.len;
    for (digits, 0..) |ch, i| {
        const remaining = len - i;
        if (i > 0 and remaining % 3 == 0) {
            buf[out_pos] = ',';
            out_pos += 1;
        }
        buf[out_pos] = ch;
        out_pos += 1;
    }

    return buf[0..out_pos];
}

const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB", "PB" };

pub fn formatFileSize(size: anytype, buf: []u8) ![]u8 {
    const T = @TypeOf(size);
    const info = @typeInfo(T);

    const fsize: f64 = switch (info) {
        .int, .comptime_int => @floatFromInt(size),
        .float, .comptime_float => @floatCast(size),
        else => @compileError("formatFileSize: expected int or float, got " ++ @typeName(T)),
    };

    var value = fsize;
    var unit_index: usize = 0;

    while (value >= 1024.0 and unit_index < units.len - 1) {
        value /= 1024.0;
        unit_index += 1;
    }

    if (unit_index == 0) {
        return std.fmt.bufPrint(buf, "{d} {s}", .{ @as(u64, @intFromFloat(value)), units[unit_index] });
    } else {
        return std.fmt.bufPrint(buf, "{d:.2} {s}", .{ value, units[unit_index] });
    }
}
