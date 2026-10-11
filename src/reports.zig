const std = @import("std");

const accounting = @import("accounting.zig");
const commodity = @import("commodity.zig");
const time = @import("time.zig");

pub const ReportError = error{Overflow};

const BalanceKey = struct {
    account: accounting.AccountId,
    commodity: commodity.CommodityId,
};

pub const Balance = struct {
    account: accounting.AccountId,
    amount: commodity.Amount,
};

pub const BalanceReport = struct {
    allocator: std.mem.Allocator,
    balances: std.ArrayList(Balance),

    pub fn deinit(self: *BalanceReport) void {
        self.balances.deinit(self.allocator);
        self.* = undefined;
    }
};

pub fn calculateBalances(
    allocator: std.mem.Allocator,
    journal: *const accounting.Journal,
) (std.mem.Allocator.Error || ReportError)!BalanceReport {
    var balances: std.ArrayList(Balance) = .empty;
    errdefer balances.deinit(allocator);

    var indices = std.AutoHashMap(BalanceKey, usize).init(allocator);
    defer indices.deinit();

    for (journal.transactions.items) |transaction| {
        for (transaction.postings.items) |posting| {
            const account = journal.getAccount(posting.account).?;
            const increases_normal_balance = switch (account.account_type) {
                .asset, .expense => posting.direction == .debit,
                .liability, .equity, .income => posting.direction == .credit,
            };

            const delta = if (increases_normal_balance)
                posting.amount.value
            else
                std.math.negate(posting.amount.value) catch return error.Overflow;

            const key = BalanceKey{
                .account = posting.account,
                .commodity = posting.amount.commodity,
            };

            const result = try indices.getOrPut(key);
            const balance_index = if (result.found_existing)
                result.value_ptr.*
            else index: {
                const new_index = balances.items.len;
                try balances.append(allocator, .{
                    .account = posting.account,
                    .amount = .{
                        .value = 0,
                        .commodity = posting.amount.commodity,
                    },
                });

                result.value_ptr.* = new_index;
                break :index new_index;
            };

            balances.items[balance_index].amount.value = std.math.add(
                i64,
                balances.items[balance_index].amount.value,
                delta,
            ) catch return error.Overflow;
        }
    }

    removeZeroBalances(&balances);
    std.mem.sort(Balance, balances.items, {}, lessThanBalance);

    return .{ .allocator = allocator, .balances = balances };
}

pub fn writeBalances(writer: *std.Io.Writer, journal: *const accounting.Journal, report: *const BalanceReport) !void {
    for (report.balances.items) |balance| {
        const account = journal.getAccount(balance.account).?;

        try writer.print("{s:<45} ", .{account.name});
        try journal.catalog.writeAmount(writer, balance.amount);
        try writer.writeByte('\n');
    }
}

fn removeZeroBalances(balances: *std.ArrayList(Balance)) void {
    var destination: usize = 0;

    for (balances.items) |balance| {
        if (balance.amount.value == 0) {
            continue;
        }

        balances.items[destination] = balance;
        destination += 1;
    }

    balances.items.len = destination;
}

fn lessThanBalance(_: void, left: Balance, right: Balance) bool {
    if (left.account != right.account) {
        return left.account < right.account;
    }

    return left.amount.commodity < right.amount.commodity;
}

test "calculate natural accounting balances" {
    var journal = try accounting.Journal.init(std.testing.allocator, 1, "personal");
    defer journal.deinit();

    const bank = try journal.addAccount("asset:bank");
    const opening = try journal.addAccount("equity:opening-balances");

    const transaction = try journal.addTransaction(null, try time.Date.parse("2026-01-01"), "Opening balance");
    const amount = try journal.catalog.parseAmount("1000.00", "AUD");

    try journal.addPosting(transaction, .debit, bank, amount);
    try journal.addPosting(transaction, .credit, opening, amount);

    var report = try calculateBalances(std.testing.allocator, &journal);
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 2), report.balances.items.len);
    try std.testing.expectEqual(@as(i64, 100_000), report.balances.items[0].amount.value);
    try std.testing.expectEqual(@as(i64, 100_000), report.balances.items[1].amount.value);

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    try writeBalances(&output.writer, &journal, &report);

    try std.testing.expectEqualStrings(
        \\asset:bank                                    1000.00 AUD
        \\equity:opening-balances                       1000.00 AUD
        \\
    , output.written());
}

test "report separate balances per commodity" {
    var journal = try accounting.Journal.init(std.testing.allocator, 1, "multi-currency");
    defer journal.deinit();

    const cash = try journal.addAccount("asset:cash");
    const opening = try journal.addAccount("equity:opening-balances");

    const aud_transaction = try journal.addTransaction(null, try time.Date.parse("2026-01-01"), "AUD opening balance");
    const aud = try journal.catalog.parseAmount("100.00", "AUD");

    try journal.addPosting(aud_transaction, .debit, cash, aud);
    try journal.addPosting(aud_transaction, .credit, opening, aud);

    const usd_transaction = try journal.addTransaction(null, try time.Date.parse("2026-01-01"), "USD opening balance");
    const usd = try journal.catalog.parseAmount("50.00", "USD");

    try journal.addPosting(usd_transaction, .debit, cash, usd);
    try journal.addPosting(usd_transaction, .credit, opening, usd);

    var report = try calculateBalances(std.testing.allocator, &journal);
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 4), report.balances.items.len);
}
