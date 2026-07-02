const std = @import("std");
const data_structures = @import("galley").data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

pub const indentation_syntax = false;
pub const Payload = struct {};

pub fn reduction_Start(args: *ProcedureArguments) void {
    if (args.context.verbosityLevel() > 0)
        std.debug.print("Parsed Lisp successfully.\n", .{});
}
