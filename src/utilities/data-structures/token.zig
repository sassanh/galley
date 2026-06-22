const builtin = @import("builtin");
const std = @import("std");
const Context = @import("context.zig").Context;
const parser = @import("parser");

pub const Token = struct {
    pub const max_length = 65500; //@max(6, parser.parse_table.longest_terminal_length);
    buffer: [Token.max_length * 2]u8 = undefined,
    head: Context.Size = 0,
    len: Context.Size = 0,

    const Self = @This();

    pub inline fn reset(self: *Self) void {
        self.head = 0;
        self.len = 0;
    }

    pub inline fn append(self: *Self, char: u8) void {
        std.debug.assert(self.len < Self.max_length);

        self.buffer[self.head] = char;
        self.head += 1;
        self.len += 1;
    }

    pub inline fn pop(self: *Self, amount: Context.Size) void {
        std.debug.assert(self.len >= amount);

        self.len -= amount;
        if (self.head - self.len >= Self.max_length) {
            const remaining = self.len;
            @memcpy(self.buffer[0..remaining], self.items());
            self.head = remaining;
        }
    }

    pub inline fn items(self: *const Self) []const u8 {
        return self.buffer[self.head - self.len .. self.head];
    }

    pub inline fn at(self: *const Self, offset: Context.Size) u8 {
        std.debug.assert(offset < self.len);
        return self.buffer[self.head + offset - self.len];
    }
};
