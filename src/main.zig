const std = @import("std");

const cli = @import("cli.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

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
