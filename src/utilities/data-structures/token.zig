const builtin = @import("builtin");
const std = @import("std");

pub const Token = struct {
    pub const max_length = 512;
    buffer: [Token.max_length * 2]u8 = undefined,
    head: usize = 0,
    len: usize = 0,

    const Self = @This();

    pub inline fn append(self: *Self, char: u8) void {
        // if (builtin.mode == .Debug and self.len == Token.max_length) {
        //     std.log.err("Token got bigger than {d} characters.\n", .{Self.max_length});
        //     return error.TokenOverflow;
        // }
        self.buffer[self.head] = char;
        self.head += 1;
        self.len += 1;
    }

    pub inline fn pop(self: *Self, len: usize) void {
        // if (builtin.mode == .Debug and self.len < len) {
        //     std.log.err("Token has length of {d} and can't be popped by {d}!\n", .{ self.len, len });
        //     return error.TokenOverflow;
        // }
        self.len -= len;
        if (self.head - self.len >= Self.max_length) {
            @memcpy(self.buffer[0..self.len], self.items());
            self.head = self.len;
        }
    }

    pub inline fn items(self: *const Self) []const u8 {
        return self.buffer[self.head - self.len .. self.head];
    }
};
