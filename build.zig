const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap = b.dependency("clap", .{});

    const languages_path = "languages";
    var dir = try b.build_root.handle.openDir(b.graph.io, languages_path, .{ .iterate = true });
    defer dir.close(b.graph.io);

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    const test_step = b.step("test", "Run tests");

    while (try walker.next(b.graph.io)) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;

        inline for ([_][]const u8{ "ll", "lr" }) |parser_type| {
            const parser_path = try std.fs.path.join(
                b.allocator,
                &[_][]const u8{ languages_path, entry.path, "_" ++ parser_type ++ "-" ++ "parser.zig" },
            );
            defer b.allocator.free(parser_path);

            const procedures_path = try std.fs.path.join(
                b.allocator,
                &[_][]const u8{ languages_path, entry.path, "procedures.zig" },
            );
            defer b.allocator.free(procedures_path);

            // Check if file exists in this subdirectory
            const exists = b.build_root.handle.access(b.graph.io, parser_path, .{});
            if (exists) |_| {
                const procedures_mod = b.addModule("procedures", .{
                    .root_source_file = b.path(procedures_path),
                    .target = target,
                });

                const parser_mod = b.addModule("parser", .{
                    .root_source_file = b.path(parser_path),
                    .target = target,
                });

                const parser_name = try std.mem.concat(
                    b.allocator,
                    u8,
                    &[_][]const u8{ parser_type, "-", entry.path },
                );
                const galley_mod = b.createModule(.{
                    .root_source_file = b.path("src/main.zig"),
                    .target = target,
                    .optimize = optimize,
                    .link_libc = true,
                    .imports = &.{
                        .{ .name = "clap", .module = clap.module("clap") },
                        .{ .name = "procedures", .module = procedures_mod },
                        .{ .name = "parser", .module = parser_mod },
                    },
                });
                galley_mod.addImport("galley", galley_mod);
                procedures_mod.addImport("galley", galley_mod);
                parser_mod.addImport("galley", galley_mod);

                const exe = b.addExecutable(.{
                    .name = parser_name,
                    // .use_llvm = false,
                    // .use_lld = false,
                    .root_module = galley_mod,
                });

                const install_artifact = b.addInstallArtifact(exe, .{});

                const result = try std.mem.concat(
                    b.allocator,
                    u8,
                    &[_][]const u8{ "Run the ", entry.path, " compiler" },
                );
                defer b.allocator.free(result);

                const compile_desc = try std.mem.concat(
                    b.allocator,
                    u8,
                    &[_][]const u8{ "Compile the ", entry.path, " compiler" },
                );
                defer b.allocator.free(compile_desc);
                const compile_step_name = try std.mem.concat(
                    b.allocator,
                    u8,
                    &[_][]const u8{ "compile-", parser_name },
                );
                defer b.allocator.free(compile_step_name);
                const compile_step = b.step(compile_step_name, compile_desc);
                compile_step.dependOn(&install_artifact.step);

                const run_step = b.step(parser_name, result);

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
                // File doesn't exist in this subdir - ignore
                if (err != error.FileNotFound) return err;
            }
        }
    }
}
