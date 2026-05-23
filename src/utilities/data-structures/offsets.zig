const builtin = @import("builtin");
const std = @import("std");

pub const Offsets = struct {
    const max_length = 512;
    buffer: [Self.max_length * 2]i8 = undefined,
    head: usize = 0,
    len: usize = 0,

    const Self = @This();

    pub inline fn append(self: *Self, offset: i8) void {
        // if (builtin.mode == .Debug and self.len == Self.max_length) {
        //     std.log.err("Offsets got bigger than {d} characters.\n", .{Self.max_length});
        //     return error.OffsetsOverflow;
        // }
        self.buffer[self.head] = offset;
        self.head += 1;
        self.len += 1;
    }

    pub inline fn pop(self: *Self, len: usize) void {
        // if (builtin.mode == .Debug and self.len < len) {
        //     std.log.err("Offsets has length of {d} and can't be popped by {d}!\n", .{ self.len, len });
        //     return error.OffsetsOverflow;
        // }
        self.len -= len;
        if (self.head - self.len >= Self.max_length) {
            @memcpy(self.buffer[0..self.len], self.buffer[self.head - self.len .. self.head]);
            self.head = self.len;
        }
    }

    pub inline fn sum(self: *const Self, start: usize, end: usize) u16 {
        var sum_: i16 = 0;
        for (self.buffer[self.head - self.len + start .. self.head - self.len + end]) |item| {
            sum_ += item;
        }
        return @intCast(sum_);
    }
};
