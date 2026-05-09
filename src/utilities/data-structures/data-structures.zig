pub const ASTNode = @import("astnode.zig").ASTNode(parser.procedures.Payload);
pub const Offsets = @import("offsets.zig").Offsets;
pub const Token = @import("token.zig").Token;

const std = @import("std");
const builtin = @import("builtin");
const parser = @import("parser");

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
        pub const Entry = struct {
            K,
            V,
        };

        entries: []const Entry,

        pub fn initComptime(comptime kvs: []const Entry) @This() {
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

        pub fn get(self: @This(), key: K) ?V {
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
        pub const Entry = struct {
            []const u8,
            V,
        };

        entries: []const Entry,
        min_len: usize,
        max_len: usize,
        keys_slice: []const []const u8,

        pub fn initComptime(comptime kvs: []const Entry) @This() {
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

        pub fn get(self: @This(), key: []const u8) ?V {
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

        pub fn getLongestPrefix(self: @This(), input: []const u8) ?Entry {
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

        pub fn keys(self: @This()) []const []const u8 {
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

        pub fn keys_terator(self: @This()) KeyIterator {
            return .{ .entries = self.entries };
        }
    };
}

pub const ProcedureArguments = struct {
    test "simple test" {
        const gpa = std.testing.allocator;
        var list: std.ArrayList(i32) = .empty;
        defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
        try list.append(gpa, 42);
        try std.testing.expectEqual(@as(i32, 42), list.pop());
    }

    allocator: std.mem.Allocator,
    io: std.Io,
    verbosity: usize,
    rule: ?Rule,
    node: ?*ASTNode,
};

pub const Procedure = fn (args: *ProcedureArguments) anyerror!void;

pub fn wrap_procedure(comptime Signature: type, comptime procedure: anytype, comptime procedure_name: []const u8) Signature {
    const signature_type_info = @typeInfo(Signature);

    if (signature_type_info != .@"fn") {
        @compileError(std.fmt.comptimePrint("{s} procedure: Expected a function signature, got {s}", .{
            procedure_name,
            @typeName(Signature),
        }));
    }

    const signature_fn_info = signature_type_info.@"fn";

    if (signature_fn_info.params.len != 1) {
        @compileError(std.fmt.comptimePrint("{s} procedure: Signature must take exactly one argument (a struct)", .{
            procedure_name,
        }));
    }

    const ArgType = signature_fn_info.params[0].type orelse @compileError(std.fmt.comptimePrint("{s} procedure: Generic parameters not allwoed here", .{
        procedure_name,
    }));
    const arg_type_info = @typeInfo(ArgType);

    const ProcedureType = @TypeOf(procedure);
    const procedure_type_info = @typeInfo(ProcedureType);

    if (procedure_type_info != .@"fn") {
        @compileError(std.fmt.comptimePrint("{s} procedure: Expected a function, got {s}", .{
            procedure_name,
            @typeName(ProcedureType),
        }));
    }

    const procedure_fn_info = procedure_type_info.@"fn";

    if (procedure_fn_info.params.len > 1) {
        @compileError(std.fmt.comptimePrint("{s} procedure: Handler must take at most one argument (a struct)", .{
            procedure_name,
        }));
    }

    if (procedure_fn_info.return_type) |ReturnType| {
        const return_type_info = @typeInfo(ReturnType);

        if (ReturnType != void and
            (return_type_info != .error_union or return_type_info.error_union.payload != void))
        {
            @compileError(std.fmt.comptimePrint("{s} procedure: Handler must return {any} or {any}, got {any}", .{
                procedure_name,
                void,
                anyerror!void,
                ReturnType,
            }));
        }
    } else {
        @compileError(std.fmt.comptimePrint("{s} procedure: Handler must return '{any}'", .{
            procedure_name,
            void,
        }));
    }

    if (procedure_fn_info.params.len == 1) {
        const ProcedureArgType = procedure_fn_info.params[0].type orelse @compileError(std.fmt.comptimePrint("{s} procedure: Generic parameters not allowed here", .{
            procedure_name,
        }));

        if (ProcedureArgType != *ProcedureArguments) {
            @compileError(std.fmt.comptimePrint("{s} procedure: Handler argument must be of type '{any}'", .{
                procedure_name,
                *ProcedureArguments,
            }));
        }

        const procedure_arg_type_info = @typeInfo(@typeInfo(ProcedureArgType).pointer.child);
        inline for (procedure_arg_type_info.@"struct".fields) |field| {
            if (!@hasField(arg_type_info.pointer.child, field.name)) {
                @compileError(std.fmt.comptimePrint("{s} procedure: Args is missing required field: '{s}'", .{
                    procedure_name,
                    field.name,
                }));
            }
        }
    }

    const Wrapper = struct {
        fn call(args: ArgType) anyerror!void {
            if (procedure_fn_info.params.len == 0) {
                return procedure();
            }

            return @call(.auto, procedure, .{args});
        }
    };

    return Wrapper.call;
}
