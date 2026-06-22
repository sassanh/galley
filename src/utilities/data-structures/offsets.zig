const builtin = @import("builtin");
const std = @import("std");
const Context = @import("context.zig").Context;
const parser = @import("parser");

pub const Offsets = struct {
    pub const max_length = @max(6, parser.parse_table.longest_terminal_length);
    buffer: [Self.max_length * 2]i8 = undefined,
    head: Context.Size = 0,
    len: Context.Size = 0,

    const Self = @This();

    pub fn reset(self: *Self) void {
        self.head = 0;
        self.len = 0;
    }

    pub inline fn append(self: *Self, offset: i8) void {
        std.debug.assert(self.len < Self.max_length);

        self.buffer[self.head] = offset;
        self.head += 1;
        self.len += 1;
    }

    pub inline fn pop(self: *Self, amount: Context.Size) void {
        std.debug.assert(self.len >= amount);

        self.len -= amount;
        if (self.head - self.len >= Self.max_length) {
            @memcpy(self.buffer[0..self.len], self.buffer[self.head - self.len .. self.head]);
            self.head = self.len;
        }
    }

    pub inline fn sum(self: *const Self, start: Context.Size, end: Context.Size) Context.Size {
        var sum_: i16 = 0;
        for (self.buffer[self.head - self.len + start .. self.head - self.len + end]) |item| {
            sum_ += item;
        }
        return @intCast(sum_);
    }
};
