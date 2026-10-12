const std = @import("std");
const commodity = @import("commodity.zig");
const time = @import("time.zig");

pub const AccountId = u32;
pub const TransactionIndex = u32;

pub const AccountType = enum {
    asset,
    liability,
    equity,
    income,
    expense,
};

pub const Account = struct {
    name: []const u8,
    account_type: AccountType,
    commodity: ?commodity.CommodityId,
};

pub const Direction = enum { debit, credit };

pub const Posting = struct {
    direction: Direction,
    account: AccountId,
    amount: commodity.Amount,
    valuation: ?commodity.Amount,
};

pub const NewPosting = struct {
    direction: Direction,
    account: AccountId,
    amount: commodity.Amount,
    valuation: ?commodity.Amount = null,
};

pub const Transaction = struct {
    id: ?[]const u8,
    date: time.Date,
    narration: ?[]const u8,
    note: ?[]const u8,
    tags: std.ArrayList([]const u8),
    postings: std.ArrayList(Posting),
};

pub const NewTransaction = struct {
    date: time.Date,
    id: ?[]const u8 = null,
    narration: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

pub const JournalError = error{
    InvalidAccountName,
    DuplicateAccount,
    DuplicateTransactionId,
    DuplicateTransactionTag,
    InvalidTransactionId,
    InvalidTransactionNote,
    InvalidTransactionTag,
    UnknownAccount,
    UnknownCommodity,
    AccountCommodityMismatch,
    UnknownTransaction,
    InvalidPostingAmount,
    InvalidPostingValuation,
    RedundantPostingValuation,
    TooManyAccounts,
    TooManyTransactions,
};

pub const ValidationError = error{
    UnsupportedVersion,
    EmptyJournalName,
    TooFewPostings,
    MultipleCommodities,
    TransactionTotalOverflow,
    UnbalancedTransaction,
};

pub const Journal = struct {
    allocator: std.mem.Allocator,

    version: u32,
    name: []const u8,

    catalog: commodity.Catalog,

    accounts: std.ArrayList(Account),
    account_ids_by_name: std.StringHashMap(AccountId),

    transactions: std.ArrayList(Transaction),
    transaction_indices_by_id: std.StringHashMap(TransactionIndex),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, version: u32, name: []const u8) !Self {
        var catalog = try commodity.Catalog.init(allocator);
        errdefer catalog.deinit();

        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);

        return .{
            .allocator = allocator,
            .version = version,
            .name = owned_name,
            .catalog = catalog,
            .accounts = .empty,
            .account_ids_by_name = std.StringHashMap(AccountId).init(allocator),
            .transactions = .empty,
            .transaction_indices_by_id = std.StringHashMap(TransactionIndex).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.transaction_indices_by_id.deinit();

        for (self.transactions.items) |*transaction| {
            if (transaction.narration) |narration| {
                self.allocator.free(narration);
            }
            if (transaction.id) |id| {
                self.allocator.free(id);
            }
            if (transaction.note) |note| {
                self.allocator.free(note);
            }
            for (transaction.tags.items) |tag| {
                self.allocator.free(tag);
            }

            transaction.tags.deinit(self.allocator);
            transaction.postings.deinit(self.allocator);
        }

        self.transactions.deinit(self.allocator);
        self.account_ids_by_name.deinit();

        for (self.accounts.items) |account| {
            self.allocator.free(account.name);
        }

        self.accounts.deinit(self.allocator);
        self.catalog.deinit();
        self.allocator.free(self.name);

        self.* = undefined;
    }

    pub fn addAccount(self: *Self, name: []const u8) !AccountId {
        return self.addAccountWithCommodity(name, null);
    }

    pub fn addAccountWithCommodity(
        self: *Self,
        name: []const u8,
        account_commodity: ?commodity.CommodityId,
    ) !AccountId {
        if (!isValidAccountName(name)) {
            return error.InvalidAccountName;
        }

        const root_end = std.mem.indexOfScalar(u8, name, ':') orelse name.len;
        const account_type = std.meta.stringToEnum(AccountType, name[0..root_end]) orelse
            return error.InvalidAccountName;

        if (self.account_ids_by_name.contains(name)) {
            return error.DuplicateAccount;
        }

        if (account_commodity) |commodity_id| {
            if (self.catalog.get(commodity_id) == null) {
                return error.UnknownCommodity;
            }
        }

        if (self.accounts.items.len > std.math.maxInt(AccountId)) {
            return error.TooManyAccounts;
        }

        try self.accounts.ensureUnusedCapacity(self.allocator, 1);
        try self.account_ids_by_name.ensureUnusedCapacity(1);

        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        const id: AccountId = @intCast(self.accounts.items.len);

        self.accounts.appendAssumeCapacity(.{
            .name = owned_name,
            .account_type = account_type,
            .commodity = account_commodity,
        });
        self.account_ids_by_name.putAssumeCapacityNoClobber(owned_name, id);

        return id;
    }

    pub fn findAccount(self: *const Self, name: []const u8) ?AccountId {
        return self.account_ids_by_name.get(name);
    }

    pub fn getAccount(self: *const Self, id: AccountId) ?Account {
        const index = std.math.cast(usize, id) orelse return null;

        if (index >= self.accounts.items.len) {
            return null;
        }

        return self.accounts.items[index];
    }

    pub fn addTransaction(self: *Self, new_transaction: NewTransaction) !TransactionIndex {
        if (new_transaction.id) |id| {
            if (id.len == 0) {
                return error.InvalidTransactionId;
            }

            if (self.transaction_indices_by_id.contains(id)) {
                return error.DuplicateTransactionId;
            }
        }

        if (new_transaction.note) |note| {
            if (note.len == 0) {
                return error.InvalidTransactionNote;
            }
        }

        if (self.transactions.items.len > std.math.maxInt(TransactionIndex)) {
            return error.TooManyTransactions;
        }

        try self.transactions.ensureUnusedCapacity(self.allocator, 1);
        if (new_transaction.id != null) {
            try self.transaction_indices_by_id.ensureUnusedCapacity(1);
        }

        var owned_narration: ?[]u8 = null;
        errdefer if (owned_narration) |narration| {
            self.allocator.free(narration);
        };

        if (new_transaction.narration) |narration| {
            owned_narration = try self.allocator.dupe(u8, narration);
        }

        var owned_id: ?[]u8 = null;
        errdefer if (owned_id) |id| {
            self.allocator.free(id);
        };

        if (new_transaction.id) |id| {
            owned_id = try self.allocator.dupe(u8, id);
        }

        var owned_note: ?[]u8 = null;
        errdefer if (owned_note) |note| {
            self.allocator.free(note);
        };

        if (new_transaction.note) |note| {
            owned_note = try self.allocator.dupe(u8, note);
        }

        const index: TransactionIndex = @intCast(self.transactions.items.len);
        self.transactions.appendAssumeCapacity(.{
            .date = new_transaction.date,
            .narration = owned_narration,
            .id = owned_id,
            .note = owned_note,
            .tags = .empty,
            .postings = .empty,
        });

        if (owned_id) |id| {
            self.transaction_indices_by_id.putAssumeCapacityNoClobber(id, index);
        }

        return index;
    }

    pub fn addTransactionTag(self: *Self, transaction_index: TransactionIndex, tag: []const u8) !void {
        const index = std.math.cast(usize, transaction_index) orelse return error.UnknownTransaction;

        if (index >= self.transactions.items.len) {
            return error.UnknownTransaction;
        }

        if (!isValidTag(tag)) {
            return error.InvalidTransactionTag;
        }

        const transaction = &self.transactions.items[index];
        for (transaction.tags.items) |existing| {
            if (std.mem.eql(u8, existing, tag)) {
                return error.DuplicateTransactionTag;
            }
        }

        const owned = try self.allocator.dupe(u8, tag);
        errdefer self.allocator.free(owned);

        try transaction.tags.append(self.allocator, owned);
    }

    pub fn addPosting(self: *Self, transaction_index: TransactionIndex, new_posting: NewPosting) !void {
        const index = std.math.cast(usize, transaction_index) orelse return error.UnknownTransaction;
        if (index >= self.transactions.items.len) {
            return error.UnknownTransaction;
        }

        const account = self.getAccount(new_posting.account) orelse {
            return error.UnknownAccount;
        };

        if (self.catalog.get(new_posting.amount.commodity) == null) {
            return error.UnknownCommodity;
        }

        if (account.commodity) |account_commodity| {
            if (account_commodity != new_posting.amount.commodity) {
                return error.AccountCommodityMismatch;
            }
        }

        if (new_posting.amount.value <= 0) {
            return error.InvalidPostingAmount;
        }

        if (new_posting.valuation) |valuation| {
            if (self.catalog.get(valuation.commodity) == null) {
                return error.UnknownCommodity;
            }

            if (valuation.value <= 0) {
                return error.InvalidPostingValuation;
            }

            if (valuation.commodity == new_posting.amount.commodity) {
                return error.RedundantPostingValuation;
            }
        }

        try self.transactions.items[index].postings.append(
            self.allocator,
            .{
                .direction = new_posting.direction,
                .account = new_posting.account,
                .amount = new_posting.amount,
                .valuation = new_posting.valuation,
            },
        );
    }

    pub fn validate(self: *const Self) !void {
        if (self.version != 1) {
            return error.UnsupportedVersion;
        }

        if (self.name.len == 0) {
            return error.EmptyJournalName;
        }

        for (0..self.transactions.items.len) |index| {
            try self.validateTransaction(@intCast(index));
        }
    }

    pub fn validateTransaction(self: *const Self, transaction_index: TransactionIndex) !void {
        const index = std.math.cast(usize, transaction_index) orelse return error.UnknownTransaction;
        if (index >= self.transactions.items.len) {
            return error.UnknownTransaction;
        }

        const transaction = self.transactions.items[index];
        if (transaction.postings.items.len < 2) {
            return error.TooFewPostings;
        }

        const first = transaction.postings.items[0];
        const first_effective = first.valuation orelse first.amount;
        const expected_commodity = first_effective.commodity;

        var debit_total: i64 = 0;
        var credit_total: i64 = 0;

        for (transaction.postings.items) |posting| {
            const effective = posting.valuation orelse posting.amount;
            if (effective.commodity != expected_commodity) {
                return error.MultipleCommodities;
            }

            switch (posting.direction) {
                .debit => {
                    debit_total = std.math.add(
                        i64,
                        debit_total,
                        effective.value,
                    ) catch return error.TransactionTotalOverflow;
                },
                .credit => {
                    credit_total = std.math.add(
                        i64,
                        credit_total,
                        effective.value,
                    ) catch return error.TransactionTotalOverflow;
                },
            }
        }

        if (debit_total != credit_total) {
            return error.UnbalancedTransaction;
        }
    }
};

// === PRIVATE HELPER FUNCTIONS ===

fn isValidAccountName(name: []const u8) bool {
    if (name.len == 0) {
        return false;
    }

    var at_component_start = true;
    for (name) |char| {
        if (char == ':') {
            if (at_component_start) {
                return false;
            }

            at_component_start = true;
            continue;
        }

        if (at_component_start) {
            if (char < 'a' or char > 'z') {
                return false;
            }

            at_component_start = false;
            continue;
        }

        const valid =
            (char >= 'a' and char <= 'z') or
            (char >= '0' and char <= '9') or
            char == '-' or
            char == '_';

        if (!valid) {
            return false;
        }
    }

    return !at_component_start;
}

fn isValidTag(tag: []const u8) bool {
    if (tag.len == 0 or tag[0] < 'a' or tag[0] > 'z') {
        return false;
    }

    for (tag[1..]) |char| {
        const valid =
            (char >= 'a' and char <= 'z') or
            (char >= '0' and char <= '9') or
            char == '-' or
            char == '_';

        if (!valid) {
            return false;
        }
    }

    return true;
}

test "construct basic journal" {
    var journal = try Journal.init(
        std.testing.allocator,
        1,
        "personal",
    );
    defer journal.deinit();

    const bank = try journal.addAccount("asset:bank");
    const transaction = try journal.addTransaction(.{ .date = try time.Date.init(2026, .jan, 1) });
    const amount = try journal.catalog.parseAmount("1000.00", "AUD");

    try journal.addPosting(transaction, .{
        .direction = .debit,
        .account = bank,
        .amount = amount,
    });

    try std.testing.expectEqual(@as(usize, 1), journal.accounts.items.len);
    try std.testing.expectEqual(AccountType.asset, journal.accounts.items[0].account_type);
    try std.testing.expectError(error.InvalidAccountName, journal.addAccount("assets:bank"));
    try std.testing.expectEqual(@as(usize, 1), journal.transactions.items.len);
    try std.testing.expectEqual(@as(usize, 1), journal.transactions.items[0].postings.items.len);

    const opening = try journal.addAccount("equity:opening-balances");

    try journal.addPosting(transaction, .{
        .direction = .credit,
        .account = opening,
        .amount = amount,
    });
    try journal.validate();
}

test "reject unbalanced transaction" {
    var journal = try Journal.init(std.testing.allocator, 1, "personal");
    defer journal.deinit();

    const bank = try journal.addAccount("asset:bank");
    const groceries = try journal.addAccount("expense:groceries");

    const transaction = try journal.addTransaction(.{ .date = try time.Date.init(2026, .jan, 17), .narration = "Groceries" });

    try journal.addPosting(transaction, .{
        .direction = .debit,
        .account = groceries,
        .amount = try journal.catalog.parseAmount("20.00", "AUD"),
    });
    try journal.addPosting(transaction, .{
        .direction = .credit,
        .account = bank,
        .amount = try journal.catalog.parseAmount("19.00", "AUD"),
    });

    try std.testing.expectError(error.UnbalancedTransaction, journal.validate());
}

test "validate stock purchase using total valuation" {
    var journal = try Journal.init(std.testing.allocator, 1, "investments");
    defer journal.deinit();

    _ = try journal.catalog.add(.{
        .symbol = "NZX.AIR",
        .kind = .security,
        .scale = 6,
    });

    const shares = try journal.addAccount("asset:broker:shares");
    const bank = try journal.addAccount("asset:bank");
    const fees = try journal.addAccount("expense:broker-fees");
    const transaction = try journal.addTransaction(.{
        .date = try time.Date.parse("2026-02-02"),
        .narration = "Buy shares",
    });

    const quantity = try journal.catalog.parseAmount("10.000000", "NZX.AIR");
    const valuation = try journal.catalog.parseAmount("7.80", "NZD");

    try journal.addPosting(transaction, .{
        .direction = .debit,
        .account = shares,
        .amount = quantity,
        .valuation = valuation,
    });
    try journal.addPosting(transaction, .{
        .direction = .debit,
        .account = fees,
        .amount = try journal.catalog.parseAmount("1.00", "NZD"),
    });
    try journal.addPosting(transaction, .{
        .direction = .credit,
        .account = bank,
        .amount = try journal.catalog.parseAmount("8.80", "NZD"),
    });

    try journal.validateTransaction(transaction);

    const stored = journal.transactions.items[transaction].postings.items[0];
    try std.testing.expect(stored.amount.eql(quantity));
    try std.testing.expect(stored.valuation.?.eql(valuation));
}

test "validate currency conversion using total valuation" {
    var journal = try Journal.init(std.testing.allocator, 1, "personal");
    defer journal.deinit();

    const aud_bank = try journal.addAccount("asset:bank:aud");
    const nzd_bank = try journal.addAccount("asset:bank:nzd");
    const fees = try journal.addAccount("expense:currency-fees");
    const transaction = try journal.addTransaction(.{
        .date = try time.Date.parse("2026-02-01"),
    });

    try journal.addPosting(transaction, .{
        .direction = .debit,
        .account = aud_bank,
        .amount = try journal.catalog.parseAmount("89.00", "AUD"),
    });
    try journal.addPosting(transaction, .{
        .direction = .debit,
        .account = fees,
        .amount = try journal.catalog.parseAmount("1.00", "AUD"),
    });
    try journal.addPosting(transaction, .{
        .direction = .credit,
        .account = nzd_bank,
        .amount = try journal.catalog.parseAmount("100.00", "NZD"),
        .valuation = try journal.catalog.parseAmount("90.00", "AUD"),
    });

    try journal.validateTransaction(transaction);
}

test "reject invalid and redundant posting valuations" {
    var journal = try Journal.init(std.testing.allocator, 1, "investments");
    defer journal.deinit();

    _ = try journal.catalog.add(.{
        .symbol = "NZX.AIR",
        .kind = .security,
        .scale = 6,
    });

    const shares = try journal.addAccount("asset:broker:shares");
    const transaction = try journal.addTransaction(.{
        .date = try time.Date.parse("2026-02-02"),
    });
    const quantity = try journal.catalog.parseAmount("10.000000", "NZX.AIR");
    const nzd = journal.catalog.find("NZD").?;

    try std.testing.expectError(
        error.InvalidPostingValuation,
        journal.addPosting(transaction, .{
            .direction = .debit,
            .account = shares,
            .amount = quantity,
            .valuation = .{ .value = 0, .commodity = nzd },
        }),
    );

    try std.testing.expectError(
        error.RedundantPostingValuation,
        journal.addPosting(transaction, .{
            .direction = .debit,
            .account = shares,
            .amount = quantity,
            .valuation = try journal.catalog.parseAmount("7.000000", "NZX.AIR"),
        }),
    );
}

test "reject unvalued mixed commodities and unbalanced valuations" {
    var journal = try Journal.init(std.testing.allocator, 1, "personal");
    defer journal.deinit();

    _ = try journal.catalog.add(.{
        .symbol = "NZX.AIR",
        .kind = .security,
        .scale = 6,
    });

    const shares = try journal.addAccount("asset:broker:shares");
    const bank = try journal.addAccount("asset:bank");

    const mixed = try journal.addTransaction(.{
        .date = try time.Date.parse("2026-02-01"),
    });
    try journal.addPosting(mixed, .{
        .direction = .debit,
        .account = bank,
        .amount = try journal.catalog.parseAmount("90.00", "AUD"),
    });
    try journal.addPosting(mixed, .{
        .direction = .credit,
        .account = bank,
        .amount = try journal.catalog.parseAmount("100.00", "NZD"),
    });
    try std.testing.expectError(error.MultipleCommodities, journal.validateTransaction(mixed));

    const unbalanced = try journal.addTransaction(.{
        .date = try time.Date.parse("2026-02-02"),
    });
    try journal.addPosting(unbalanced, .{
        .direction = .debit,
        .account = shares,
        .amount = try journal.catalog.parseAmount("10.000000", "NZX.AIR"),
        .valuation = try journal.catalog.parseAmount("7.80", "NZD"),
    });
    try journal.addPosting(unbalanced, .{
        .direction = .credit,
        .account = bank,
        .amount = try journal.catalog.parseAmount("8.00", "NZD"),
    });
    try std.testing.expectError(error.UnbalancedTransaction, journal.validateTransaction(unbalanced));
}
