const std = @import("std");

const accounting = @import("accounting.zig");
const loader = @import("loader.zig");
const reports = @import("reports.zig");
const source_manager = @import("source_manager.zig");
const time = @import("time.zig");
const workspace = @import("workspace.zig");

pub const BalanceQuery = union(enum) {
    all,
    prefix: struct {
        value: []const u8,
        sort: reports.BalanceSort = .account,
    },
};

pub const InspectQuery = struct {
    id: ?[]const u8 = null,
    account: ?[]const u8 = null,
    from: ?time.Date = null,
    to: ?time.Date = null,
    tag: ?[]const u8 = null,
};

pub const BalanceResult = union(enum) {
    all: reports.BalanceReport,
    prefix: reports.PrefixBalanceReport,

    pub fn deinit(self: *BalanceResult) void {
        switch (self.*) {
            .all => |*report| report.deinit(),
            .prefix => |*report| report.deinit(),
        }

        self.* = undefined;
    }
};

pub const LoadFailure = struct {
    failure: loader.Failure,
    sources: *const source_manager.SourceManager,
};

pub const Application = struct {
    allocator: std.mem.Allocator,
    loaded_workspace: workspace.Workspace,

    pub fn load(
        allocator: std.mem.Allocator,
        io: std.Io,
        dir: std.Io.Dir,
        path: []const u8,
    ) !Application {
        return .{
            .allocator = allocator,
            .loaded_workspace = try workspace.load(allocator, io, dir, path),
        };
    }

    pub fn deinit(self: *Application) void {
        self.loaded_workspace.deinit();
        self.* = undefined;
    }

    pub fn journal(self: *const Application) ?*const accounting.Journal {
        return switch (self.loaded_workspace.result) {
            .journal => |*captured_journal| captured_journal,
            .failure => null,
        };
    }

    pub fn loadFailure(self: *const Application) ?LoadFailure {
        return switch (self.loaded_workspace.result) {
            .journal => null,
            .failure => |failure| .{
                .failure = failure,
                .sources = &self.loaded_workspace.sources,
            },
        };
    }

    pub fn inspect(self: *const Application, query: InspectQuery) !reports.InspectReport {
        const loaded_journal = self.journal() orelse return error.JournalUnavailable;

        if (query.id) |id| {
            if (loaded_journal.findTransactionById(id) == null) {
                return error.UnknownTransaction;
            }
        }

        const account_id = if (query.account) |account|
            loaded_journal.findAccount(account) orelse return error.UnknownAccount
        else
            null;

        return reports.inspectTransactions(self.allocator, loaded_journal, .{
            .id = query.id,
            .account = account_id,
            .from = query.from,
            .to = query.to,
            .tag = query.tag,
        });
    }

    pub fn balances(self: *const Application, query: BalanceQuery) !BalanceResult {
        const loaded_journal = self.journal() orelse return error.JournalUnavailable;

        return switch (query) {
            .all => .{
                .all = try reports.calculateBalances(self.allocator, loaded_journal),
            },
            .prefix => |options| .{
                .prefix = try reports.calculatePrefixBalances(
                    self.allocator,
                    loaded_journal,
                    options.value,
                    options.sort,
                ),
            },
        };
    }
};

test "load application and calculate balances" {
    var application = try Application.load(
        std.testing.allocator,
        std.testing.io,
        std.Io.Dir.cwd(),
        "tests/fixtures/activity-coverage/journal.fiscus",
    );
    defer application.deinit();

    try std.testing.expect(application.journal() != null);

    var result = try application.balances(.all);
    defer result.deinit();

    switch (result) {
        .all => |report| {
            try std.testing.expectEqual(@as(usize, 21), report.balances.items.len);
        },
        .prefix => return error.UnexpectedBalanceResult,
    }

    var prefix_result = try application.balances(.{
        .prefix = .{
            .value = "asset:bank:nzd",
            .sort = .amount,
        },
    });
    defer prefix_result.deinit();

    switch (prefix_result) {
        .prefix => |report| {
            try std.testing.expectEqual(@as(usize, 2), report.balances.items.len);
            try std.testing.expectEqual(@as(usize, 1), report.amounts.items.len);
        },
        .all => return error.UnexpectedBalanceResult,
    }

    var inspect_result = try application.inspect(.{
        .id = "salary-2026-01",
        .account = "asset:bank:nzd:everyday",
    });
    defer inspect_result.deinit();
    try std.testing.expectEqual(@as(usize, 1), inspect_result.transactions.items.len);

    try std.testing.expectError(
        error.UnknownTransaction,
        application.inspect(.{ .id = "missing" }),
    );
    try std.testing.expectError(
        error.UnknownAccount,
        application.inspect(.{ .account = "asset:missing" }),
    );
}

test "queries require a valid journal" {
    var application = try Application.load(
        std.testing.allocator,
        std.testing.io,
        std.Io.Dir.cwd(),
        "tests/fixtures/unbalanced.fiscus",
    );
    defer application.deinit();

    try std.testing.expect(application.journal() == null);

    const load_failure = application.loadFailure() orelse return error.ExpectedLoadFailure;
    _ = load_failure.failure;
    try std.testing.expect(load_failure.sources.files.items.len > 0);

    try std.testing.expectError(error.JournalUnavailable, application.balances(.all));
}
