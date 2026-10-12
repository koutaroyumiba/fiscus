const std = @import("std");
const fiscus = @import("fiscus");

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
    if (args.len < 2) {
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

    var prefix: ?[]const u8 = null;
    switch (command) {
        .check => {
            if (args.len != 3) {
                try writeUsage(stderr);
                return 2;
            }
        },
        .balance => {
            if (args.len == 5 and std.mem.eql(u8, args[3], "--prefix")) {
                prefix = args[4];
            } else if (args.len != 3) {
                try writeUsage(stderr);
                return 2;
            }

            if (prefix) |value| {
                if (!fiscus.accounting.isValidAccountPrefix(value)) {
                    try stderr.print("fis: invalid account prefix '{s}'\n", .{value});
                    return 2;
                }
            }
        },
    }

    const file_name = args[2];
    var workspace = fiscus.workspace.load(allocator, io, std.Io.Dir.cwd(), file_name) catch |err| {
        try stderr.print("fis: cannot load '{s}': {s}\n", .{ file_name, @errorName(err) });
        return 1;
    };
    defer workspace.deinit();

    return switch (workspace.result) {
        .journal => |journal| {
            switch (command) {
                .check => {
                    try stdout.print("{s}: valid\n", .{file_name});
                },
                .balance => {
                    if (prefix) |value| {
                        var report = fiscus.reports.calculatePrefixBalances(allocator, &journal, value) catch |err| switch (err) {
                            error.OutOfMemory => return error.OutOfMemory,
                            error.InvalidAccountPrefix => unreachable,
                            error.Overflow => {
                                try stderr.writeAll("fis: account balance overflow\n");
                                return 1;
                            },
                        };
                        defer report.deinit();

                        try fiscus.reports.writePrefixBalances(stdout, &journal, value, &report);
                    } else {
                        var report = fiscus.reports.calculateBalances(allocator, &journal) catch |err| switch (err) {
                            error.OutOfMemory => return error.OutOfMemory,
                            error.Overflow => {
                                try stderr.writeAll("fis: account balance overflow\n");
                                return 1;
                            },
                        };
                        defer report.deinit();

                        try fiscus.reports.writeBalances(stdout, &journal, &report);
                    }
                },
            }

            return 0;
        },
        .failure => |failure| {
            const diagnostic = fiscus.diagnostics.fromLoadFailure(failure);
            try fiscus.diagnostics.writeFromManager(stderr, &workspace.sources, diagnostic);
            return 1;
        },
    };
}

fn writeUsage(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\usage:
        \\  fis check <file>
        \\  fis balance <file> [--prefix <account>]
        \\
    );
}
