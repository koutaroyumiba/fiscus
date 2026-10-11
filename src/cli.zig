const std = @import("std");
const fiscus = @import("fiscus");

const MAX_FILE_SIZE = 16 * 1024 * 1024;

pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: []const [:0]const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    if (args.len != 3 or !std.mem.eql(u8, args[1], "check")) {
        try stderr.print("usage: fis check <file>\n", .{});
        return 2;
    }

    const file_name = args[2];
    const input = std.Io.Dir.cwd().readFileAlloc(io, file_name, allocator, .limited(MAX_FILE_SIZE)) catch |err| {
        try stderr.print("fis: cannot read '{s}': {s}\n", .{ file_name, @errorName(err) });
        return 1;
    };
    defer allocator.free(input);

    var result = try fiscus.loader.load(allocator, input);
    defer result.deinit();

    return switch (result) {
        .journal => {
            try stdout.print("{s}: valid\n", .{file_name});
            return 0;
        },
        .failure => |failure| {
            const diagnostic = fiscus.diagnostics.fromLoadFailure(failure);
            try fiscus.diagnostics.write(stderr, file_name, input, diagnostic);
            return 1;
        },
    };
}
