const clap = @import("clap");
const root = @import("root");
const std = @import("std");

const c = @cImport({
    @cInclude("signal.h");
    @cInclude("stdlib.h");
    @cInclude("setjmp.h");
});

pub const procedures = @import("procedures");
pub const parse_table = @import("parse-table");
pub const read_chunk_size = 128 * 1024;

const data_structures = root.data_structures;

threadlocal var jmp_env_ptr: ?*c.sigjmp_buf = null;
export fn segv_handler(sig: c_int, info: [*c]c.siginfo_t, ucontext: ?*anyopaque) callconv(.c) void {
    _ = sig;
    _ = info;
    _ = ucontext;

    // If the thread that segfaulted was actively parsing, jump back to safety.
    if (jmp_env_ptr) |env| {
        c.siglongjmp(env, 1);
    }

    // If it was null, this is a legitimate bug somewhere else in your codebase.
    // Let it crash normally.
    c.abort();
}

pub fn parse(init: std.process.Init) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                          Display this help and exit.
        \\-v, --verbosity <VERBOSITY_LEVEL>   An option parameter, which takes a value.
        \\-r, --iterations <ITERATIONS>       Repeat the parse process. Useful for benchmarking.
        \\<FILE>
        \\
    );
    const parsers = comptime .{
        .VERBOSITY_LEVEL = clap.parsers.int(usize, 10),
        .ITERATIONS = clap.parsers.int(usize, 10),
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

    const io = init.io;

    const program_file = if (res.positionals[0]) |path|
        try std.Io.Dir.cwd().openFile(init.io, path, .{
            .mode = .read_only,
            .lock = .exclusive,
        })
    else
        std.Io.File.stdin();

    try stack_overflow_protected_run(program_file, verbosity, iterations, io);
}

fn stack_overflow_protected_run(program_file: std.Io.File, verbosity: usize, iterations: usize, io: std.Io) !void {
    var context = data_structures.Context{ .verbosity = verbosity };

    // 1. Allocate the Alternate Signal Stack
    // macOS requires MINSIGSTKSZ, but giving it an extra 8KB is safest.
    const alt_stack_size = c.SIGSTKSZ + 8192;
    const alt_stack_mem = try std.heap.page_allocator.alloc(u8, alt_stack_size);
    defer std.heap.page_allocator.free(alt_stack_mem);

    var ss: c.stack_t = undefined;
    ss.ss_sp = alt_stack_mem.ptr;
    ss.ss_size = alt_stack_mem.len;
    ss.ss_flags = 0;

    if (c.sigaltstack(&ss, null) != 0) {
        return error.SignalSetupFailed;
    }

    // 2. Register the Signal Handler
    var sa: c.struct_sigaction = undefined;
    sa.__sigaction_u.__sa_sigaction = segv_handler;
    _ = c.sigemptyset(&sa.sa_mask);

    // SA_ONSTACK is mandatory: it forces the OS to use our alt_stack_mem
    sa.sa_flags = c.SA_SIGINFO | c.SA_ONSTACK;

    _ = c.sigaction(c.SIGSEGV, &sa, null);
    _ = c.sigaction(c.SIGBUS, &sa, null); // macOS sometimes throws SIGBUS for guard pages

    // 3. Prepare the Jump Target
    var env: c.sigjmp_buf = undefined;
    jmp_env_ptr = &env;

    // Critical: Clean up the pointer when done parsing so a later segfault
    // elsewhere in your app doesn't accidentally jump back here.
    defer jmp_env_ptr = null;

    // 4. The Zero-Cost Trap
    // sigsetjmp returns 0 on the direct execution path.
    // It returns 1 when arriving here asynchronously via siglongjmp.
    const val = c.sigsetjmp(&env, 0);

    if (val == 0) {
        // --- HOT PATH ---
        // Absolutely zero overhead. No depth counting. No pointer checks.
        // LLVM will aggressively inline and unroll the parser.
        const start = std.Io.Clock.awake.now(io);

        for (0..iterations) |_| {
            var reader_buffer: [read_chunk_size * 2]u8 = undefined;
            context.reader = program_file.reader(io, &reader_buffer);
            context.reset();

            try parse_table.parse(&context);
        }

        if (iterations > 1) {
            const end = std.Io.Clock.awake.now(io);
            const duration = start.durationTo(end);
            const elapsed_ns: usize = @intCast(duration.toNanoseconds());
            const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
            const mbps = @as(f64, @floatFromInt(context.parsed_bytes)) / duration_secs;

            var buffer: [64]u8 = undefined;
            std.debug.print("Parsed bytes:  {s}\n", .{try root.string_utilities.formatFileSize(context.parsed_bytes, &buffer)});
            std.debug.print("Duration:      {s} ns\n", .{try root.string_utilities.formatWithThousands(elapsed_ns, &buffer)});
            std.debug.print("Throughput:    {s}/s\n", .{try root.string_utilities.formatFileSize(mbps, &buffer)});
        }
    } else {
        // --- RECOVERY PATH ---
        // We arrived here from the signal handler because the hardware MMU caught an overflow.
        var padding: [10]u8 = undefined;
        @memset(padding[0..10], ' ');
        std.debug.print("\x1b[35mStackOverflow at {d}:{d}:\x1b[0m\n" ++
            "Surounding text: \x1b[37m\"{f}\"\n" ++
            "                  {s}^\x1b[0m\n" ++
            "Token content: \x1b[37m\"{f}\"\x1b[34m\x1b[0m\n", .{
            context.line,
            context.column,
            root.string_utilities.fmtString(
                context.chunk_buffer[context.seek - (context.seek % 10) .. context.seek + (10 - (context.seek % 10))],
            ),
            padding[0..(context.seek % 10)],
            root.string_utilities.fmtString(context.token.items()),
        });
        return error.StackOverflow;
    }
}
