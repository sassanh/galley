const std = @import("std");
const data_structures = @import("root").data_structures;

pub const Payload = struct { data: []const u8 = "" };

pub fn reduction_Start() void {
    std.debug.print("Parser started successfully.\n", .{});
}
