const clap = @import("clap");
const std = @import("std");

pub const procedures = @import("procedures");
pub const parser = @import("parser");
pub const string_utilities = @import("utilities/string.zig");
pub const stack_overflow_utilities = @import("utilities/stack-overflow.zig");
pub const data_structures = @import("utilities/data-structures/data-structures.zig");
pub const read_chunk_size = std.math.maxInt(std.math.Min(data_structures.Context.Size, u28));
pub const preallocated_nodes = if (parser.is_ast_enabled) (std.math.maxInt(std.math.Min(data_structures.Context.Size, u27)) - 1) else 0;

fn printHelp() void {
    std.debug.print("\nusage: parser_builder [program_path]\n", .{});
    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                        Display this help and exit.
        \\-v, --verbosity <VERBOSITY_LEVEL> An option parameter, which takes a value.
        \\-r, --iterations <ITERATIONS>     Repeat the parse process. Useful for benchmarking.
        \\-w, --warmup-iterations <ITERATIONS>
        \\                                  Warmup iterations of the parse process.
        \\                                  Useful for benchmarking.
        \\    --disable-stack-overflow-recovery
        \\                                  Disables the stack overflow recovery mechanism
        \\<FILE>
        \\
    );

    const parsers = comptime .{
        .VERBOSITY_LEVEL = clap.parsers.int(u8, 10),
        .ITERATIONS = clap.parsers.int(u32, 10),
        .FILE = clap.parsers.string,
    };
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = init.gpa,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
        const stdout = &stdout_writer.interface;

        try clap.usageToFile(init.io, .stdout(), clap.Help, &params);
        _ = try stdout.writeAll("\n\n");
        try stdout.flush();
        return clap.helpToFile(init.io, .stdout(), clap.Help, &params, .{});
    }

    const verbosity = if (res.args.verbosity) |verbosity| verbosity else 0;
    const iterations = if (res.args.iterations) |iterations| iterations else 1;
    const warmup_iterations = if (@field(res.args, "warmup-iterations")) |warmup_iterations| warmup_iterations else iterations / 10;

    const io = init.io;

    const program_file = if (res.positionals[0]) |path|
        try std.Io.Dir.cwd().openFile(init.io, path, .{
            .mode = .read_only,
            .lock = .exclusive,
        })
    else
        std.Io.File.stdin();

    const arena_allocator = init.arena.allocator();

    const reader_buffer = try init.gpa.alloc(u8, read_chunk_size * 2);
    defer init.gpa.free(reader_buffer);

    var allocator = try data_structures.ASTAllocator.init_capacity(arena_allocator);

    var context = data_structures.Context{
        .node_allocator = &allocator,
        .arena_allocator = arena_allocator,
        .verbosity = verbosity,
        .io = io,
        .reader = program_file.reader(io, reader_buffer),
        .chunk_buffer = try init.gpa.alloc(u8, read_chunk_size),
    };
    defer init.gpa.free(context.chunk_buffer);

    if (@field(res.args, "disable-stack-overflow-recovery") > 0)
        try run(&context, warmup_iterations, iterations)
    else
        try stack_overflow_utilities.protected_run(run, &context, warmup_iterations, iterations);
}

fn run(context: *data_structures.Context, warmup_iterations: usize, iterations: usize) !void {
    for (0..warmup_iterations) |_| {
        try context.reset();

        try parser.parse(context);
    }

    var total_parsed_bytes: usize = 0;
    const start = std.Io.Clock.awake.now(context.io);

    for (0..iterations) |_| {
        try context.reset();

        try parser.parse(context);
        total_parsed_bytes += context.pos();
    }

    if (iterations > 1) {
        const end = std.Io.Clock.awake.now(context.io);
        const duration = start.durationTo(end);
        const elapsed_ns: usize = @intCast(duration.toNanoseconds());
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(total_parsed_bytes)) / duration_secs;

        var buffer: [64]u8 = undefined;
        std.debug.print("Parsed bytes:  {s}\n", .{try string_utilities.formatFileSize(total_parsed_bytes, &buffer)});
        std.debug.print("Duration:      {s} ns\n", .{try string_utilities.formatWithThousands(elapsed_ns, &buffer)});
        std.debug.print("Throughput:    {s}/s\n", .{try string_utilities.formatFileSize(mbps, &buffer)});
        std.debug.print("Nodes allocated:    {s}\n", .{try string_utilities.formatWithThousands(
            context.node_allocator.counter,
            &buffer,
        )});
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test {
    _ = @import("utilities/data-structures/astnode.zig");
}
