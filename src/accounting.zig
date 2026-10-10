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
};

pub const Direction = enum { debit, credit };

pub const Posting = struct {
    direction: Direction,
    account: AccountId,
    amount: commodity.Amount,
};

pub const Transaction = struct {
    external_id: ?[]const u8,
    date: time.Date,
    description: []const u8,
    postings: std.ArrayList(Posting),
};

pub const JournalError = error{
    InvalidAccountName,
    DuplicateAccount,
    DuplicateTransactionId,
    InvalidTransactionId,
    UnknownAccount,
    UnknownCommodity,
    UnknownTransaction,
    InvalidPostingAmount,
    TooManyAccounts,
    TooManyTransactions,
};

pub const Journal = struct {
    allocator: std.mem.Allocator,

    version: u32,
    name: []const u8,

    catalog: commodity.Catalog,

    accounts: std.ArrayList(Account),
    account_ids_by_name: std.StringHashMap(AccountId),

    transactions: std.ArrayList(Transaction),
    transaction_indices_by_external_id: std.StringHashMap(TransactionIndex),

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
            .transaction_indices_by_external_id = std.StringHashMap(TransactionIndex).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.transaction_indices_by_external_id.deinit();

        for (self.transactions.items) |*transaction| {
            if (transaction.external_id) |external_id| {
                self.allocator.free(external_id);
            }

            self.allocator.free(transaction.description);
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
        if (!isValidAccountName(name)) {
            return error.InvalidAccountName;
        }

        const root_end = std.mem.indexOfScalar(u8, name, ':') orelse name.len;
        const account_type = std.meta.stringToEnum(AccountType, name[0..root_end]) orelse
            return error.InvalidAccountName;

        if (self.account_ids_by_name.contains(name)) {
            return error.DuplicateAccount;
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

    pub fn addTransaction(self: *Self, external_id: ?[]const u8, date: time.Date, description: []const u8) !TransactionIndex {
        if (external_id) |id| {
            if (id.len == 0) {
                return error.InvalidTransactionId;
            }

            if (self.transaction_indices_by_external_id.contains(id)) {
                return error.DuplicateTransactionId;
            }
        }

        if (self.transactions.items.len > std.math.maxInt(TransactionIndex)) {
            return error.TooManyTransactions;
        }

        try self.transactions.ensureUnusedCapacity(self.allocator, 1);
        if (external_id != null) {
            try self.transaction_indices_by_external_id.ensureUnusedCapacity(1);
        }

        const owned_description = try self.allocator.dupe(u8, description);
        errdefer self.allocator.free(owned_description);

        var owned_external_id: ?[]u8 = null;
        errdefer if (owned_external_id) |id| {
            self.allocator.free(id);
        };

        if (external_id) |id| {
            owned_external_id = try self.allocator.dupe(u8, id);
        }

        const index: TransactionIndex = @intCast(self.transactions.items.len);
        self.transactions.appendAssumeCapacity(.{
            .external_id = owned_external_id,
            .date = date,
            .description = owned_description,
            .postings = .empty,
        });

        if (owned_external_id) |id| {
            self.transaction_indices_by_external_id.putAssumeCapacityNoClobber(id, index);
        }

        return index;
    }

    pub fn addPosting(self: *Self, transaction_index: TransactionIndex, direction: Direction, account: AccountId, amount: commodity.Amount) !void {
        const index = std.math.cast(usize, transaction_index) orelse return error.UnknownTransaction;
        if (index >= self.transactions.items.len) {
            return error.UnknownTransaction;
        }

        if (self.getAccount(account) == null) {
            return error.UnknownAccount;
        }

        if (self.catalog.get(amount.commodity) == null) {
            return error.UnknownCommodity;
        }

        if (amount.value <= 0) {
            return error.InvalidPostingAmount;
        }

        try self.transactions.items[index].postings.append(
            self.allocator,
            .{ .direction = direction, .account = account, .amount = amount },
        );
    }

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
};

test "construct basic journal" {
    var journal = try Journal.init(
        std.testing.allocator,
        1,
        "personal",
    );
    defer journal.deinit();

    const bank = try journal.addAccount("asset:bank");
    const transaction = try journal.addTransaction(null, try time.Date.init(2026, .jan, 1), "Opening balance");
    const amount = try journal.catalog.parseAmount("1000.00", "AUD");

    try journal.addPosting(transaction, .debit, bank, amount);

    try std.testing.expectEqual(@as(usize, 1), journal.accounts.items.len);
    try std.testing.expectEqual(AccountType.asset, journal.accounts.items[0].account_type);
    try std.testing.expectError(error.InvalidAccountName, journal.addAccount("assets:bank"));
    try std.testing.expectEqual(@as(usize, 1), journal.transactions.items.len);
    try std.testing.expectEqual(@as(usize, 1), journal.transactions.items[0].postings.items.len);
}
