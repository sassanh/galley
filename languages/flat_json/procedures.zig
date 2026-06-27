const std = @import("std");
const data_structures = @import("root").data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;
const string_utilities = @import("root").string_utilities;

pub const indentation_syntax = false;
pub const Payload = struct {
    objects: u32 = 0,
    arrays: u32 = 0,
    nulls: u32 = 0,
};
