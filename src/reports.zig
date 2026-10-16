const std = @import("std");

const accounting = @import("accounting.zig");
const commodity = @import("commodity.zig");
const time = @import("time.zig");

pub const ReportError = error{Overflow};

const BalanceKey = struct {
    account: accounting.AccountId,
    commodity: commodity.CommodityId,
};

pub const BalanceSort = enum {
    account,
    amount,
};

pub const Balance = struct {
    account: accounting.AccountId,
    amount: commodity.Amount,
};

pub const InspectFilter = struct {
    account: ?accounting.AccountId = null,
    from: ?time.Date = null,
    to: ?time.Date = null,
    tag: ?[]const u8 = null,
};

pub const InspectReport = struct {
    allocator: std.mem.Allocator,
    transactions: std.ArrayList(accounting.TransactionIndex),

    pub fn deinit(self: *InspectReport) void {
        self.transactions.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const BalanceReport = struct {
    allocator: std.mem.Allocator,
    balances: std.ArrayList(Balance),

    pub fn deinit(self: *BalanceReport) void {
        self.balances.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const PrefixBalanceReport = struct {
    allocator: std.mem.Allocator,
    amounts: std.ArrayList(commodity.Amount),
    balances: std.ArrayList(Balance),

    pub fn deinit(self: *PrefixBalanceReport) void {
        self.balances.deinit(self.allocator);
        self.amounts.deinit(self.allocator);
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

pub fn calculatePrefixBalances(
    allocator: std.mem.Allocator,
    journal: *const accounting.Journal,
    prefix: []const u8,
    sort: BalanceSort,
) (std.mem.Allocator.Error || ReportError || error{InvalidAccountPrefix})!PrefixBalanceReport {
    if (!accounting.isValidAccountPrefix(prefix)) {
        return error.InvalidAccountPrefix;
    }

    var amounts: std.ArrayList(commodity.Amount) = .empty;
    errdefer amounts.deinit(allocator);

    var balances: std.ArrayList(Balance) = .empty;
    errdefer balances.deinit(allocator);

    var indices = std.AutoHashMap(commodity.CommodityId, usize).init(allocator);
    defer indices.deinit();

    var all_balances = try calculateBalances(allocator, journal);
    defer all_balances.deinit();

    for (all_balances.balances.items) |balance| {
        const account = journal.getAccount(balance.account).?;
        if (!accounting.matchesAccountPrefix(account.name, prefix)) {
            continue;
        }

        try balances.append(allocator, balance);

        const result = try indices.getOrPut(balance.amount.commodity);
        const amount_index = if (result.found_existing)
            result.value_ptr.*
        else index: {
            const new_index = amounts.items.len;
            try amounts.append(allocator, .{
                .value = 0,
                .commodity = balance.amount.commodity,
            });
            result.value_ptr.* = new_index;
            break :index new_index;
        };

        amounts.items[amount_index].value = std.math.add(
            i64,
            amounts.items[amount_index].value,
            balance.amount.value,
        ) catch return error.Overflow;
    }

    std.mem.sort(commodity.Amount, amounts.items, {}, lessThanAmount);
    std.mem.sort(
        Balance,
        balances.items,
        PrefixSortContext{ .journal = journal, .sort = sort },
        lessThanPrefixBalance,
    );

    return .{
        .allocator = allocator,
        .amounts = amounts,
        .balances = balances,
    };
}

pub fn inspectTransactions(
    allocator: std.mem.Allocator,
    journal: *const accounting.Journal,
    filter: InspectFilter,
) std.mem.Allocator.Error!InspectReport {
    var transactions: std.ArrayList(accounting.TransactionIndex) = .empty;
    errdefer transactions.deinit(allocator);

    for (journal.transactions.items, 0..) |transaction, index| {
        if (filter.from) |from| {
            if (transaction.date.order(from) == .lt) {
                continue;
            }
        }

        if (filter.to) |to| {
            if (transaction.date.order(to) == .gt) {
                continue;
            }
        }

        if (filter.account) |account| {
            var found = false;
            for (transaction.postings.items) |posting| {
                if (posting.account == account) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                continue;
            }
        }

        if (filter.tag) |tag| {
            var found = false;
            for (transaction.tags.items) |transaction_tag| {
                if (std.mem.eql(u8, transaction_tag, tag)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                continue;
            }
        }

        try transactions.append(allocator, @intCast(index));
    }

    std.mem.sort(
        accounting.TransactionIndex,
        transactions.items,
        journal,
        lessThanTransaction,
    );

    return .{ .allocator = allocator, .transactions = transactions };
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

fn lessThanAmount(_: void, left: commodity.Amount, right: commodity.Amount) bool {
    return left.commodity < right.commodity;
}

fn lessThanTransaction(
    journal: *const accounting.Journal,
    left: accounting.TransactionIndex,
    right: accounting.TransactionIndex,
) bool {
    const left_transaction = journal.transactions.items[left];
    const right_transaction = journal.transactions.items[right];

    return switch (left_transaction.date.order(right_transaction.date)) {
        .lt => true,
        .gt => false,
        .eq => left < right,
    };
}

const PrefixSortContext = struct {
    journal: *const accounting.Journal,
    sort: BalanceSort,
};

fn lessThanPrefixBalance(
    context: PrefixSortContext,
    left: Balance,
    right: Balance,
) bool {
    if (left.amount.commodity != right.amount.commodity) {
        return left.amount.commodity < right.amount.commodity;
    }

    const left_name = context.journal.getAccount(left.account).?.name;
    const right_name = context.journal.getAccount(right.account).?.name;

    if (context.sort == .amount and left.amount.value != right.amount.value) {
        return left.amount.value > right.amount.value;
    }

    return std.mem.lessThan(u8, left_name, right_name);
}

test "calculate natural accounting balances" {
    var journal = try accounting.Journal.init(std.testing.allocator, 1, "personal");
    defer journal.deinit();

    const bank = try journal.addAccount("asset:bank");
    const opening = try journal.addAccount("equity:opening-balances");

    const transaction = try journal.addTransaction(.{
        .date = try time.Date.parse("2026-01-01"),
        .narration = "Opening balance",
    });
    const amount = try journal.catalog.parseAmount("1000.00", "AUD");

    try journal.addPosting(transaction, .{
        .direction = .debit,
        .account = bank,
        .amount = amount,
    });
    try journal.addPosting(transaction, .{
        .direction = .credit,
        .account = opening,
        .amount = amount,
    });

    var report = try calculateBalances(std.testing.allocator, &journal);
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 2), report.balances.items.len);
    try std.testing.expectEqual(@as(i64, 100_000), report.balances.items[0].amount.value);
    try std.testing.expectEqual(@as(i64, 100_000), report.balances.items[1].amount.value);
}

test "aggregate balances by component-aware account prefix" {
    var journal = try accounting.Journal.init(std.testing.allocator, 1, "prefixes");
    defer journal.deinit();

    const checking = try journal.addAccount("asset:bank:checking");
    const savings = try journal.addAccount("asset:bank:savings");
    const banking = try journal.addAccount("asset:banking");
    const opening = try journal.addAccount("equity:opening-balances");
    const aud = try journal.catalog.parseAmount("100.00", "AUD");
    const larger_aud = try journal.catalog.parseAmount("200.00", "AUD");
    const usd = try journal.catalog.parseAmount("25.00", "USD");

    const entries = [_]struct { account: accounting.AccountId, amount: commodity.Amount }{
        .{ .account = checking, .amount = aud },
        .{ .account = savings, .amount = larger_aud },
        .{ .account = checking, .amount = usd },
        .{ .account = banking, .amount = aud },
    };

    for (entries, 0..) |entry, index| {
        const transaction = try journal.addTransaction(.{
            .date = try time.Date.init(2026, .jan, @intCast(index + 1)),
        });
        try journal.addPosting(transaction, .{
            .direction = .debit,
            .account = entry.account,
            .amount = entry.amount,
        });
        try journal.addPosting(transaction, .{
            .direction = .credit,
            .account = opening,
            .amount = entry.amount,
        });
    }

    var report = try calculatePrefixBalances(std.testing.allocator, &journal, "asset:bank", .account);
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 2), report.amounts.items.len);
    try std.testing.expectEqual(@as(usize, 3), report.balances.items.len);
    try std.testing.expectEqual(@as(i64, 30_000), report.amounts.items[0].value);
    try std.testing.expectEqual(@as(i64, 2_500), report.amounts.items[1].value);
    try std.testing.expectEqual(checking, report.balances.items[0].account);
    try std.testing.expectEqual(savings, report.balances.items[1].account);

    var amount_sorted = try calculatePrefixBalances(
        std.testing.allocator,
        &journal,
        "asset:bank",
        .amount,
    );
    defer amount_sorted.deinit();

    try std.testing.expectEqual(savings, amount_sorted.balances.items[0].account);
    try std.testing.expectEqual(checking, amount_sorted.balances.items[1].account);

    try std.testing.expectError(
        error.InvalidAccountPrefix,
        calculatePrefixBalances(std.testing.allocator, &journal, "asset:Bank", .account),
    );
}

test "inspect transactions with structured filters and chronological ordering" {
    var journal = try accounting.Journal.init(std.testing.allocator, 1, "personal");
    defer journal.deinit();

    const bank = try journal.addAccount("asset:bank");
    const groceries = try journal.addAccount("expense:groceries");
    const opening = try journal.addAccount("equity:opening-balances");
    const amount = try journal.catalog.parseAmount("10.00", "AUD");

    const later = try journal.addTransaction(.{
        .date = try time.Date.parse("2026-02-01"),
        .narration = "Groceries",
    });
    try journal.addTransactionTag(later, "food");
    try journal.addPosting(later, .{ .direction = .debit, .account = groceries, .amount = amount });
    try journal.addPosting(later, .{ .direction = .credit, .account = bank, .amount = amount });

    const earlier = try journal.addTransaction(.{
        .date = try time.Date.parse("2026-01-01"),
        .narration = "Opening balance",
    });
    try journal.addPosting(earlier, .{ .direction = .debit, .account = bank, .amount = amount });
    try journal.addPosting(earlier, .{ .direction = .credit, .account = opening, .amount = amount });

    var all = try inspectTransactions(std.testing.allocator, &journal, .{});
    defer all.deinit();
    try std.testing.expectEqualSlices(
        accounting.TransactionIndex,
        &.{ earlier, later },
        all.transactions.items,
    );

    var filtered = try inspectTransactions(std.testing.allocator, &journal, .{
        .account = groceries,
        .from = try time.Date.parse("2026-02-01"),
        .to = try time.Date.parse("2026-02-01"),
        .tag = "food",
    });
    defer filtered.deinit();
    try std.testing.expectEqualSlices(
        accounting.TransactionIndex,
        &.{later},
        filtered.transactions.items,
    );

    var no_matches = try inspectTransactions(std.testing.allocator, &journal, .{ .tag = "missing" });
    defer no_matches.deinit();
    try std.testing.expectEqual(@as(usize, 0), no_matches.transactions.items.len);
}

test "report separate balances per commodity" {
    var journal = try accounting.Journal.init(std.testing.allocator, 1, "multi-currency");
    defer journal.deinit();

    const cash = try journal.addAccount("asset:cash");
    const opening = try journal.addAccount("equity:opening-balances");

    const aud_transaction = try journal.addTransaction(.{
        .date = try time.Date.parse("2026-01-01"),
        .narration = "AUD opening balance",
    });
    const aud = try journal.catalog.parseAmount("100.00", "AUD");

    try journal.addPosting(aud_transaction, .{
        .direction = .debit,
        .account = cash,
        .amount = aud,
    });
    try journal.addPosting(aud_transaction, .{
        .direction = .credit,
        .account = opening,
        .amount = aud,
    });

    const usd_transaction = try journal.addTransaction(.{
        .date = try time.Date.parse("2026-01-01"),
        .narration = "USD opening balance",
    });
    const usd = try journal.catalog.parseAmount("50.00", "USD");

    try journal.addPosting(usd_transaction, .{
        .direction = .debit,
        .account = cash,
        .amount = usd,
    });
    try journal.addPosting(usd_transaction, .{
        .direction = .credit,
        .account = opening,
        .amount = usd,
    });

    var report = try calculateBalances(std.testing.allocator, &journal);
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 4), report.balances.items.len);
}
