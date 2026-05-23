const std = @import("std");

fn extractParseTableType(b: *std.Build, file_path: []const u8) ![]const u8 {
    const file = try b.build_root.handle.openFile(b.graph.io, file_path, .{});
    defer file.close(b.graph.io);

    var contents = try b.allocator.alloc(u8, 100 * 1024);
    _ = try file.readPositionalAll(b.graph.io, contents, 0);

    const search_str = "parse_table_type = \"";

    const start_idx = std.mem.indexOf(u8, contents, search_str) orelse {
        std.debug.print("Could not find parse_table_type in {s}\n", .{file_path});
        return error.MissingParseTableType;
    };

    const value_start = start_idx + search_str.len;

    // Find the closing quote
    const end_idx = std.mem.indexOf(u8, contents[value_start..], "\"") orelse return error.InvalidFormat;

    // Return the extracted string (allocating it using the build allocator so it lives forever)
    return b.allocator.dupe(u8, contents[value_start .. value_start + end_idx]);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("compiler_builder", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const clap = b.dependency("clap", .{});

    const languages_path = "languages";
    var dir = try b.build_root.handle.openDir(b.graph.io, languages_path, .{ .iterate = true });
    defer dir.close(b.graph.io);

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    const test_step = b.step("test", "Run tests");

    while (try walker.next(b.graph.io)) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;

        const parse_table_path = try std.fs.path.join(
            b.allocator,
            &[_][]const u8{ languages_path, entry.path, "_parse-table.zig" },
        );
        defer b.allocator.free(parse_table_path);

        const procedures_path = try std.fs.path.join(
            b.allocator,
            &[_][]const u8{ languages_path, entry.path, "procedures.zig" },
        );
        defer b.allocator.free(procedures_path);

        // Check if file exists in this subdirectory
        const exists = b.build_root.handle.access(b.graph.io, parse_table_path, .{});
        if (exists) |_| {
            if (extractParseTableType(b, parse_table_path)) |table_type| {
                const procedures_mod = b.addModule("procedures", .{
                    .root_source_file = b.path(procedures_path),
                    .target = target,
                });

                const parse_table_mod = b.addModule("parse-table", .{
                    .root_source_file = b.path(parse_table_path),
                    .target = target,
                });

                const parser_mod_src_path = b.fmt("src/{s}.zig", .{table_type});
                const parser_mod = b.addModule("parser", .{
                    .root_source_file = b.path(parser_mod_src_path),
                    .target = target,
                    .imports = &.{
                        .{ .name = "parse-table", .module = parse_table_mod },
                        .{ .name = "procedures", .module = procedures_mod },
                        .{ .name = "clap", .module = clap.module("clap") },
                    },
                });

                procedures_mod.addImport("parser", parser_mod);
                parse_table_mod.addImport("parser", parser_mod);

                const exe = b.addExecutable(.{
                    .name = entry.path,
                    // .use_llvm = false,
                    // .use_lld = false,
                    .root_module = b.createModule(.{
                        // .omit_frame_pointer = false, // required for time profiling using Instruments app
                        .root_source_file = b.path("src/main.zig"),
                        .target = target,
                        .optimize = optimize,
                        .imports = &.{
                            .{ .name = "parser", .module = parser_mod },
                        },
                    }),
                });

                const install_artifact = b.addInstallArtifact(exe, .{});

                const result = try std.mem.concat(
                    b.allocator,
                    u8,
                    &[_][]const u8{ "Run the ", entry.path, " compiler" },
                );
                defer b.allocator.free(result);

                const run_step = b.step(entry.path, result);

                const run_cmd = b.addRunArtifact(exe);
                run_step.dependOn(&install_artifact.step);
                run_step.dependOn(&run_cmd.step);

                run_cmd.step.dependOn(b.getInstallStep());

                if (b.args) |args| {
                    run_cmd.addArgs(args);
                }

                const exe_tests = b.addTest(.{
                    .root_module = exe.root_module,
                });

                const run_exe_tests = b.addRunArtifact(exe_tests);
                test_step.dependOn(&run_exe_tests.step);
            } else |err| {
                std.log.err("{}", .{err});
            }
        } else |err| {
            // File doesn't exist in this subdir - ignore
            if (err != error.FileNotFound) return err;
        }
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    test_step.dependOn(&run_mod_tests.step);
}
