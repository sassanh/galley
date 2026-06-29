const builtin = @import("builtin");
const root = @import("galley");
const std = @import("std");
const data_structures = root.data_structures;

const c = @cImport({
    @cInclude("signal.h");
    @cInclude("stdlib.h");
    @cInclude("setjmp.h");
});

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

pub fn protected_run(
    run: fn (*data_structures.Context, usize, usize) anyerror!void,
    context: *data_structures.Context,
    warmup_iterations: usize,
    iterations: usize,
) !void {
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
    if (comptime builtin.target.os.tag.isDarwin()) {
        sa.__sigaction_u.__sa_sigaction = segv_handler;
    } else {
        sa.__sigaction_handler.sa_sigaction = segv_handler;
    }
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

        try run(context, warmup_iterations, iterations);
    } else {
        // --- RECOVERY PATH ---
        // We arrived here from the signal handler because the hardware MMU caught an overflow.
        var padding: [10]u8 = undefined;
        @memset(padding[0..10], ' ');
        const pos = context.pos();
        std.debug.print("\x1b[35mStackOverflow at {d}:{d}:\x1b[0m\n" ++
            "Surounding text: \x1b[37m\"{f}\"\n" ++
            "                  {s}^\x1b[0m\n" ++
            "Token content: \x1b[37m\"{f}\"\x1b[34m\x1b[0m\n", .{
            if (comptime builtin.mode != .ReleaseFast) context.line else 0,
            if (comptime builtin.mode != .ReleaseFast) context.column else 0,
            root.string_utilities.fmtString(
                context.chunk_buffer[pos - (pos % 10) .. pos + (10 - (pos % 10))],
            ),
            padding[0..(pos % 10)],
            root.string_utilities.fmtString(context.token.items()),
        });
        return error.StackOverflow;
    }
}
