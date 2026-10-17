const std = @import("std");

const vaxis = @import("vaxis");

fn panicHandler(message: []const u8, return_addr: ?usize) noreturn {
    vaxis.recover();
    std.debug.defaultPanic(message, return_addr);
}

pub const panic = std.debug.FullPanic(panicHandler);

const cli = @import("cli.zig");
const tui = @import("tui/main.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len == 1) {
        try tui.run(init, "journal.fiscus");
        return;
    }

    if (std.mem.eql(u8, args[1], "tui") and args.len <= 3) {
        const path = if (args.len == 3) args[2] else "journal.fiscus";
        try tui.run(init, path);
        return;
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const exit_code = try cli.run(init.gpa, io, args, stdout, stderr);

    try stdout.flush();
    try stderr.flush();

    if (exit_code != 0) {
        std.process.exit(exit_code);
    }
}
