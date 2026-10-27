const std = @import("std");
const fiscus = @import("fiscus");
const render = @import("cli_render.zig");

const Command = enum {
    check,
    balance,
    inspect,
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
        else if (std.mem.eql(u8, args[1], "inspect"))
            .inspect
        else {
            try writeUsage(stderr);
            return 2;
        };

    var file_name: []const u8 = "journal.fiscus";

    var prefix: ?[]const u8 = null;
    var sort: fiscus.reports.BalanceSort = .account;
    var sort_was_set = false;
    var balance_tag: ?fiscus.reports.TagFilter = null;

    var inspect_id: ?[]const u8 = null;
    var inspect_account: ?[]const u8 = null;
    var inspect_from: ?fiscus.core.Date = null;
    var inspect_to: ?fiscus.core.Date = null;
    var inspect_tag: ?[]const u8 = null;
    var inspect_running_balance = false;

    switch (command) {
        .check => {
            if (args.len > 3) {
                try writeUsage(stderr);
                return 2;
            }
            if (args.len == 3) {
                file_name = args[2];
            }
        },
        .balance => {
            var index: usize = 2;
            if (index < args.len and !std.mem.startsWith(u8, args[index], "--")) {
                file_name = args[index];
                index += 1;
            }

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
                } else if (std.mem.eql(u8, args[index], "--tag")) {
                    if (index + 1 >= args.len or balance_tag != null) {
                        try writeUsage(stderr);
                        return 2;
                    }

                    balance_tag = .{ .exact = args[index + 1] };
                    index += 2;
                } else if (std.mem.eql(u8, args[index], "--tag-prefix")) {
                    if (index + 1 >= args.len or balance_tag != null) {
                        try writeUsage(stderr);
                        return 2;
                    }

                    balance_tag = .{ .prefix = args[index + 1] };
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
                if (!fiscus.ledger.isValidAccountPrefix(value)) {
                    try stderr.print("fis: invalid account prefix '{s}'\n", .{value});
                    return 2;
                }
            }
        },
        .inspect => {
            var index: usize = 2;
            if (index < args.len and !std.mem.startsWith(u8, args[index], "--")) {
                file_name = args[index];
                index += 1;
            }

            while (index < args.len) {
                if (std.mem.eql(u8, args[index], "--id")) {
                    if (index + 1 >= args.len or inspect_id != null) {
                        try writeUsage(stderr);
                        return 2;
                    }
                    inspect_id = args[index + 1];
                    index += 2;
                } else if (std.mem.eql(u8, args[index], "--account")) {
                    if (index + 1 >= args.len or inspect_account != null) {
                        try writeUsage(stderr);
                        return 2;
                    }
                    inspect_account = args[index + 1];
                    index += 2;
                } else if (std.mem.eql(u8, args[index], "--from")) {
                    if (index + 1 >= args.len or inspect_from != null) {
                        try writeUsage(stderr);
                        return 2;
                    }
                    const value = args[index + 1];
                    inspect_from = fiscus.core.Date.parse(value) catch {
                        try stderr.print("fis: invalid date '{s}' for --from\n", .{value});
                        return 2;
                    };
                    index += 2;
                } else if (std.mem.eql(u8, args[index], "--to")) {
                    if (index + 1 >= args.len or inspect_to != null) {
                        try writeUsage(stderr);
                        return 2;
                    }
                    const value = args[index + 1];
                    inspect_to = fiscus.core.Date.parse(value) catch {
                        try stderr.print("fis: invalid date '{s}' for --to\n", .{value});
                        return 2;
                    };
                    index += 2;
                } else if (std.mem.eql(u8, args[index], "--tag")) {
                    if (index + 1 >= args.len or inspect_tag != null) {
                        try writeUsage(stderr);
                        return 2;
                    }
                    inspect_tag = args[index + 1];
                    index += 2;
                } else if (std.mem.eql(u8, args[index], "--running-balance")) {
                    if (inspect_running_balance) {
                        try writeUsage(stderr);
                        return 2;
                    }
                    inspect_running_balance = true;
                    index += 1;
                } else {
                    try writeUsage(stderr);
                    return 2;
                }
            }

            if (inspect_from != null and inspect_to != null and inspect_from.?.order(inspect_to.?) == .gt) {
                try stderr.writeAll("fis: --from date must not be after --to date\n");
                return 2;
            }

            if (inspect_running_balance and inspect_account == null) {
                try stderr.writeAll("fis: --running-balance requires --account\n");
                return 2;
            }
        },
    }

    var application = fiscus.application.Application.load(
        allocator,
        io,
        std.Io.Dir.cwd(),
        file_name,
    ) catch |err| {
        try stderr.print("fis: cannot load '{s}': {s}\n", .{ file_name, @errorName(err) });
        return 1;
    };
    defer application.deinit();

    const journal = application.journal() orelse {
        const load_failure = application.loadFailure() orelse unreachable;
        const diagnostic = fiscus.diagnostics.fromLoadFailure(load_failure.failure);
        try fiscus.diagnostics.writeFromManager(stderr, load_failure.sources, diagnostic);
        return 1;
    };

    switch (command) {
        .check => {
            try stdout.print("{s}: valid\n", .{file_name});
        },
        .balance => {
            const query = fiscus.application.BalanceQuery{
                .scope = if (prefix) |value|
                    .{ .prefix = .{ .value = value, .sort = sort } }
                else
                    .all,
                .tag = balance_tag,
            };

            var result = application.balances(query) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.JournalUnavailable,
                error.InvalidAccountPrefix,
                => unreachable,
                error.Overflow => {
                    try stderr.writeAll("fis: account balance overflow\n");
                    return 1;
                },
            };
            defer result.deinit();

            switch (result) {
                .all => |*report| try render.writeBalances(stdout, journal, report),
                .prefix => |*report| try render.writePrefixBalances(stdout, journal, prefix.?, report),
            }
        },
        .inspect => {
            if (inspect_running_balance) {
                var report = application.accountRegister(.{
                    .account = inspect_account.?,
                    .id = inspect_id,
                    .from = inspect_from,
                    .to = inspect_to,
                    .tag = inspect_tag,
                }) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.JournalUnavailable => unreachable,
                    error.UnknownTransaction => {
                        try stderr.print("fis: unknown transaction ID '{s}'\n", .{inspect_id.?});
                        return 1;
                    },
                    error.UnknownAccount => {
                        try stderr.print("fis: unknown account '{s}'\n", .{inspect_account.?});
                        return 1;
                    },
                    error.Overflow => {
                        try stderr.writeAll("fis: account running balance overflow\n");
                        return 1;
                    },
                };
                defer report.deinit();

                try render.writeAccountRegister(stdout, journal, &report);
            } else {
                var report = application.inspect(.{
                    .id = inspect_id,
                    .account = inspect_account,
                    .from = inspect_from,
                    .to = inspect_to,
                    .tag = inspect_tag,
                }) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.JournalUnavailable => unreachable,
                    error.UnknownTransaction => {
                        try stderr.print("fis: unknown transaction ID '{s}'\n", .{inspect_id.?});
                        return 1;
                    },
                    error.UnknownAccount => {
                        try stderr.print("fis: unknown account '{s}'\n", .{inspect_account.?});
                        return 1;
                    },
                };
                defer report.deinit();

                try render.writeInspect(stdout, journal, &report);
            }
        },
    }

    return 0;
}

test {
    _ = render;
}

fn writeUsage(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\usage:
        \\  fis check [file]
        \\  fis balance [file] [--prefix <account>] [--sort account|amount] [--tag <tag> | --tag-prefix <prefix>]
        \\  fis inspect [file] [--id <id>] [--account <account>] [--from <date>] [--to <date>] [--tag <tag>] [--running-balance]
        \\
    );
}
