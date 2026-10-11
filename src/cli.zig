const std = @import("std");
const fiscus = @import("fiscus");

const MAX_FILE_SIZE = 16 * 1024 * 1024;

const Command = enum {
    check,
    balance,
};

pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: []const [:0]const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    if (args.len != 3) {
        try writeUsage(stderr);
        return 2;
    }

    const command: Command =
        if (std.mem.eql(u8, args[1], "check"))
            .check
        else if (std.mem.eql(u8, args[1], "balance"))
            .balance
        else {
            try writeUsage(stderr);
            return 2;
        };

    const file_name = args[2];
    const input = std.Io.Dir.cwd().readFileAlloc(io, file_name, allocator, .limited(MAX_FILE_SIZE)) catch |err| {
        try stderr.print("fis: cannot read '{s}': {s}\n", .{ file_name, @errorName(err) });
        return 1;
    };
    defer allocator.free(input);

    var result = try fiscus.loader.load(allocator, input);
    defer result.deinit();

    return switch (result) {
        .journal => |journal| {
            switch (command) {
                .check => {
                    try stdout.print("{s}: valid\n", .{file_name});
                },
                .balance => {
                    var report = fiscus.reports.calculateBalances(allocator, &journal) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        error.Overflow => {
                            try stderr.writeAll("fis: account balance overflow\n");
                            return 1;
                        },
                    };
                    defer report.deinit();

                    try fiscus.reports.writeBalances(stdout, &journal, &report);
                },
            }

            return 0;
        },
        .failure => |failure| {
            const diagnostic = fiscus.diagnostics.fromLoadFailure(failure);
            try fiscus.diagnostics.write(stderr, file_name, input, diagnostic);
            return 1;
        },
    };
}

fn writeUsage(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\usage:
        \\  fis check <file>
        \\  fis balance <file>
        \\
    );
}
