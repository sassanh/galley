const std = @import("std");
const root = @import("galley");
const data_structures = root.data_structures;

pub const ProcedureArguments = struct {
    test "simple test" {
        const gpa = std.testing.allocator;
        var list: std.ArrayList(i32) = .empty;
        defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
        try list.append(gpa, 42);
        try std.testing.expectEqual(@as(i32, 42), list.pop());
    }

    context: *data_structures.Context,
    rule: ?data_structures.Rule,
    node: ?data_structures.ASTNode.Pointer,
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
