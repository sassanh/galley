const std = @import("std");
const data_structures = @import("galley").data_structures;

pub const indentation_syntax = false;
pub const Payload = struct { data: []const u8 = "" };

pub fn reduction_Start() void {
    std.debug.print("Parsed successfully.\n", .{});
}
