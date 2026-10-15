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
    var sort: fiscus.reports.BalanceSort = .account;
    var sort_was_set = false;

    switch (command) {
        .check => {
            if (args.len != 3) {
                try writeUsage(stderr);
                return 2;
            }
        },
        .balance => {
            if (args.len < 3) {
                try writeUsage(stderr);
                return 2;
            }

            var index: usize = 3;
            while (index < args.len) {
                if (std.mem.eql(u8, args[index], "--prefix")) {
                    if (index + 1 >= args.len or prefix != null) {
                        try writeUsage(stderr);
                        return 2;
                    }

                    prefix = args[index + 1];
                    index += 2;
                } else if (std.mem.eql(u8, args[index], "--sort")) {
                    if (index + 1 >= args.len or sort_was_set) {
                        try writeUsage(stderr);
                        return 2;
                    }

                    const value = args[index + 1];
                    if (std.mem.eql(u8, value, "account")) {
                        sort = .account;
                    } else if (std.mem.eql(u8, value, "amount")) {
                        sort = .amount;
                    } else {
                        try stderr.print(
                            "fis: invalid sort '{s}'; expected 'account' or 'amount'\n",
                            .{value},
                        );
                        return 2;
                    }

                    sort_was_set = true;
                    index += 2;
                } else {
                    try writeUsage(stderr);
                    return 2;
                }
            }

            if (sort_was_set and prefix == null) {
                try stderr.writeAll("fis: --sort currently requires --prefix\n");
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
                        var report = fiscus.reports.calculatePrefixBalances(allocator, &journal, value, sort) catch |err| switch (err) {
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
        \\  fis balance <file>
        \\  fis balance <file> --prefix <account> [--sort account|amount]
        \\
    );
}
