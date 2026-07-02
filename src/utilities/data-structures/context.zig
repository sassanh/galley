const builtin = @import("builtin");
const root = @import("galley");
const std = @import("std");
const data_structures = root.data_structures;
const string_utilities = root.string_utilities;

fn findScalarLast(comptime T: type, slice: []const T, value: T) ?Context.Size {
    var i = slice.len;
    while (i > 0) {
        i -= 1;
        if (slice[i] == value) {
            if (comptime builtin.mode == .Debug) {
                std.debug.assert(i <= std.math.maxInt(Context.Size));
            }
            return @intCast(i);
        }
    }
    return null;
}

pub const Context = struct {
    pub const Size = root.parser.input_size_cap;

    node_allocator: *data_structures.ASTAllocator,
    arena_allocator: std.mem.Allocator,
    io: std.Io,
    input_path: ?[]const u8 = null,
    language_options: root.config.Options = .{},

    reader: std.Io.File.Reader = undefined,
    chunk_buffer: []u8 = undefined,
    line: if (builtin.mode != .ReleaseFast) u32 else void = if (builtin.mode != .ReleaseFast) 1 else {},
    column: if (builtin.mode != .ReleaseFast) u32 else void = if (builtin.mode != .ReleaseFast) 1 else {},

    token: data_structures.Token = .{},
    line_offsets: if (builtin.mode != .ReleaseFast)
        data_structures.Offsets
    else
        void = if (builtin.mode != .ReleaseFast) .{} else {},
    column_offsets: if (builtin.mode != .ReleaseFast)
        data_structures.Offsets
    else
        void = if (builtin.mode != .ReleaseFast) .{} else {},

    indent_width: u16 = 0,
    current_indent: u16 = 0,

    seek: if (root.procedures.indentation_syntax) Size else void = if (root.procedures.indentation_syntax) 0 else {},
    read_bytes: Size = 0,
    verbosity: usize,

    advance_input_mode: enum {
        without_check,
        with_check,
    } = undefined,

    const Self = @This();

    pub fn release_token(self: *@This(), length: Size) void {
        if (comptime builtin.mode != .ReleaseFast) {
            if (comptime root.procedures.indentation_syntax) {
                self.line += self.line_offsets.sum(0, length);
            }
            self.column += self.column_offsets.sum(0, length);
            var last_newline: i16 = -1;
            for ("\n\x01\x02") |newline_char| {
                if (findScalarLast(u8, self.token.items()[0..length], newline_char)) |index| {
                    if (index > last_newline) {
                        self.column = self.column_offsets.sum(index, length);
                        last_newline = @intCast(index);
                    }
                    if (comptime !root.procedures.indentation_syntax) {
                        self.line += 1;
                    }
                }
            }

            if (comptime root.procedures.indentation_syntax) {
                self.line_offsets.pop(length);
            }
            self.column_offsets.pop(length);
        }
        self.token.pop(length);
    }

    pub fn read(self: *@This()) void {
        const bytes_read = self.reader.interface.readSliceShort(self.chunk_buffer) catch |err| switch (err) {
            error.ReadFailed => return,
        };

        if (bytes_read < self.chunk_buffer.len) {
            self.chunk_buffer[bytes_read] = '\x00';
            self.advance_input_mode = .without_check;
        }
    }

    pub fn reset(self: *@This()) !void {
        self.advance_input_mode = .with_check;

        try self.reader.seekTo(0);
        self.read_bytes = 0;
        if (comptime root.procedures.indentation_syntax) {
            self.seek = 0;
        }
        if (comptime builtin.mode != .ReleaseFast) {
            self.line = 1;
            self.column = 1;
            self.line_offsets.reset();
            self.column_offsets.reset();
        }
        self.token.reset(self.chunk_buffer);
        self.node_allocator.reset();
        self.read();
    }

    pub inline fn advance_input_with_check(self: *@This()) void {
        if (comptime root.procedures.indentation_syntax) {
            if (self.seek == root.read_chunk_size - 1) {
                self.read_bytes += self.seek;
                self.seek = 0;
                self.read();
            }
            self.seek +%= 1;
        }
    }

    pub inline fn advance_input_without_check(self: *@This()) void {
        if (comptime root.procedures.indentation_syntax) {
            self.seek += 1;
        }
    }

    pub inline fn advance_input(self: *@This()) void {
        if (comptime root.procedures.indentation_syntax) {
            // if (self.advance_input_mode == .with_check) {
            //     self.advance_input_with_check();
            // } else {
            self.advance_input_without_check();
            // }
        }
    }

    pub inline fn advance_lexer(self: *@This()) void {
        if (comptime root.procedures.indentation_syntax) {
            while (self.chunk_buffer[self.seek] == '\n') {
                self.advance_input();
                var line_spaces: u16 = 0;

                while (self.chunk_buffer[self.seek] == ' ') {
                    self.advance_input();
                    line_spaces += 1;
                }

                if (self.indent_width == 0) {
                    self.indent_width = line_spaces;
                } else if (line_spaces % self.indent_width != 0) {
                    std.log.err("\x1b[35mIndentationError at line {d}:\n\x1b[0mInvalid number of spaces {d} which is not divisible by previousely detected indentation width of \x1b[31m\"{d}\"\x1b[0m.", .{
                        if (comptime builtin.mode != .ReleaseFast) self.line + 1 else 0,
                        line_spaces,
                        self.indent_width,
                    });

                    unreachable;
                }
                const new_indent = if (self.indent_width == 0) 0 else line_spaces / self.indent_width;
                if (comptime builtin.mode != .ReleaseFast and root.procedures.indentation_syntax) {
                    self.line_offsets.append(1);
                }
                if (new_indent == self.current_indent) {
                    if (comptime builtin.mode != .ReleaseFast) {
                        self.column_offsets.append(@intCast(line_spaces + 1));
                    }
                    self.token.append('\n');
                } else {
                    if (new_indent > self.current_indent) {
                        for (0..new_indent - self.current_indent) |index| {
                            if (comptime builtin.mode != .ReleaseFast) {
                                if (comptime root.procedures.indentation_syntax) {
                                    if (index != 0) {
                                        self.line_offsets.append(0);
                                    }
                                }
                                self.column_offsets.append(@intCast(new_indent * self.indent_width + 1));
                            }
                            self.token.append('\x01');
                        }
                    } else if (new_indent < self.current_indent) {
                        for (0..self.current_indent - new_indent) |index| {
                            if (comptime builtin.mode != .ReleaseFast) {
                                if (comptime root.procedures.indentation_syntax) {
                                    if (index != 0) {
                                        self.line_offsets.append(0);
                                    }
                                }
                                self.column_offsets.append(@intCast(new_indent * self.indent_width + 1));
                            }
                            self.token.append('\x02');
                        }
                    }
                    self.current_indent = new_indent;
                }
            }
        }

        if (comptime builtin.mode != .ReleaseFast) {
            if (comptime root.procedures.indentation_syntax) {
                self.line_offsets.append(0);
            }
            self.column_offsets.append(1);
        }
        if (comptime root.procedures.indentation_syntax) {
            self.token.append(self.chunk_buffer[self.seek]);
            self.advance_input();
        } else {
            self.token.append_no_copy();
        }

        if (comptime builtin.mode == .Debug) {
            if (self.verbosity > 1) {
                std.debug.print("\n{d}:{d}:\"{f}\"\n", .{
                    if (comptime builtin.mode != .ReleaseFast) self.line else 0,
                    if (comptime builtin.mode != .ReleaseFast) self.column else 0,
                    string_utilities.fmtString(self.token.items()),
                });
            }
        }
    }

    pub fn head(self: *@This(), comptime T: type, offset: Size) T {
        const bytes_needed = comptime @divExact(@bitSizeOf(T), 8);
        const needed_len = offset + bytes_needed;
        while (self.token.len < needed_len) {
            self.advance_lexer();
        }

        const base_ptr = self.token.items().ptr + offset;

        if (comptime T == u8) {
            return base_ptr[0];
        }

        const array_ptr: *const [bytes_needed]u8 = @ptrCast(base_ptr);
        return std.mem.readInt(T, array_ptr, .big);
    }

    pub inline fn pos(self: *Self) Size {
        return self.read_bytes + self.token.head - self.token.len;
    }

    pub inline fn get_text_slice(self: *const Self, start: Size, length: Size) []const u8 {
        return self.token.buffer[start .. start + length];
    }
};
