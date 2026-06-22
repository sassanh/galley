const std = @import("std");
const builtin = @import("builtin");
const parser = @import("parser");
const string_utilities = @import("root").string_utilities;

pub const Payload = parser.procedures.Payload;
pub const ASTNode = @import("astnode.zig").ASTNode(Payload);
pub const ASTAllocator = @import("astnode.zig").ASTAllocator(Payload);
pub const Context = @import("context.zig").Context;
pub const Offsets = @import("offsets.zig").Offsets;
pub const ProcedureArguments = @import("procedure-utilities.zig").ProcedureArguments;
pub const Procedure = @import("procedure-utilities.zig").Procedure;
pub const wrap_procedure = @import("procedure-utilities.zig").wrap_procedure;
pub const Token = @import("token.zig").Token;

pub const SymbolType = enum {
    variable,
    procedure,
    terminal,
    end,
};

pub const Symbol = struct {
    type: SymbolType,
    id: []const u8,
};

pub const Rule = struct {
    header: u16,
    right_hand_side: []const u16,
    right_hand_side_index: []const u8,
};

pub fn StaticIntMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        pub const Entry = struct {
            K,
            V,
        };

        entries: []const Entry,

        pub fn initComptime(comptime kvs: []const Entry) Self {
            comptime if (builtin.mode == .ReleaseSafe) {
                var i: usize = 0;
                while (i + 1 < kvs.len) : (i += 1) {
                    if (kvs[i][0] >= kvs[i + 1][0]) {
                        @compileError("Keys must be sorted!");
                    }
                }
            };

            return .{ .entries = kvs };
        }

        pub fn get(self: *const Self, key: K) ?V {
            var left: usize = 0;
            var right: usize = self.entries.len;

            while (left < right) {
                const mid = left + (right - left) / 2;
                const mid_key = self.entries[mid][0];

                if (mid_key == key) return self.entries[mid][1];
                if (mid_key < key) {
                    left = mid + 1;
                } else {
                    right = mid;
                }
            }
            return null;
        }
    };
}

pub fn StaticStringMap(comptime V: type) type {
    return struct {
        const Self = @This();

        pub const Entry = struct {
            []const u8,
            V,
        };

        entries: []const Entry,
        min_len: usize,
        max_len: usize,
        keys_slice: []const []const u8,

        pub fn initComptime(comptime kvs: []const Entry) Self {
            var min: usize = std.math.maxInt(usize);
            var max: usize = 0;

            comptime if (builtin.mode == .ReleaseSafe) {
                var i: usize = 0;
                while (i + 1 < kvs.len) : (i += 1) {
                    if (std.mem.order(u8, kvs[i][0], kvs[i + 1][0]) != .lt) {
                        @compileError("String keys must be strictly sorted and unique!");
                    }
                }
            };

            for (kvs) |kv| {
                if (kv[0].len < min) min = kv[0].len;
                if (kv[0].len > max) max = kv[0].len;
            }
            if (kvs.len == 0) {
                min = 0;
            }

            comptime var k_arr: [kvs.len][]const u8 = undefined;
            for (kvs, 0..) |kv, i| {
                k_arr[i] = kv[0];
            }

            const Static = struct {
                const keys_array = k_arr;
            };

            return .{
                .entries = kvs,
                .min_len = min,
                .max_len = max,
                .keys_slice = &Static.keys_array,
            };
        }

        pub fn get(self: *const Self, key: []const u8) ?V {
            var left: usize = 0;
            var right: usize = self.entries.len;

            while (left < right) {
                const mid = left + (right - left) / 2;
                const mid_key = self.entries[mid][0];

                switch (std.mem.order(u8, mid_key, key)) {
                    .eq => return self.entries[mid][1],
                    .lt => left = mid + 1,
                    .gt => right = mid,
                }
            }
            return null;
        }

        pub fn getLongestPrefix(self: *const Self, input: []const u8) ?Entry {
            if (self.entries.len == 0 or input.len < self.min_len) {
                return null;
            }

            var len = @min(self.max_len, input.len);

            while (len >= self.min_len) : (len -= 1) {
                const sliced_input = input[0..len];

                if (self.get(sliced_input)) |val| {
                    return .{ sliced_input, val };
                }
            }

            return null;
        }

        pub fn keys(self: *const Self) []const []const u8 {
            return self.keys_slice;
        }

        pub const KeyIterator = struct {
            entries: []const Entry,
            index: usize = 0,

            pub fn next(self: *KeyIterator) ?[]const u8 {
                if (self.index >= self.entries.len) {
                    return null;
                }
                const key = self.entries[self.index][0];
                self.index += 1;
                return key;
            }
        };

        pub fn keys_terator(self: *const Self) KeyIterator {
            return .{ .entries = self.entries };
        }
    };
}
