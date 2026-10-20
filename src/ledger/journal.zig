const std = @import("std");

const core = @import("../core/root.zig");

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

// TYPES

pub const Direction = enum { debit, credit };
pub const AccountIndex = u32;
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
    commodity: ?core.CommodityId,
};

pub const Posting = struct {
    direction: Direction,
    account: AccountIndex,
    amount: core.Amount,
    valuation: ?core.Amount,
};

pub const Transaction = struct {
    date: core.Date,
    narration: ?[]const u8,
    id: ?[]const u8,
    note: ?[]const u8,
    tags: std.ArrayList([]const u8),
    postings: std.ArrayList(Posting),
};

// transaction needs this because stupid ArrayList allocations
pub const NewTransaction = struct {
    date: core.Date,
    narration: ?[]const u8 = null,
    id: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

pub const NewPosting = struct {
    direction: Direction,
    account: AccountIndex,
    amount: core.Amount,
    valuation: ?core.Amount = null,
};

pub const Journal = struct {
    allocator: std.mem.Allocator,
    catalog: core.Catalog,

    version: u32,
    name: []const u8,
    accounts: std.ArrayList(Account),
    transactions: std.ArrayList(Transaction),

    // indices
    account_indices_by_name: std.StringHashMap(AccountIndex),
    transaction_indices_by_id: std.StringHashMap(TransactionIndex),

    pub fn init(allocator: std.mem.Allocator, version: u32, name: []const u8) !Journal {
        var catalog = try core.Catalog.init(allocator);
        errdefer catalog.deinit();

        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);

        return .{
            .allocator = allocator,
            .catalog = catalog,
            .version = version,
            .name = owned_name,
            .accounts = .empty,
            .transactions = .empty,
            .account_indices_by_name = std.StringHashMap(AccountIndex).init(allocator),
            .transaction_indices_by_id = std.StringHashMap(TransactionIndex).init(allocator),
        };
    }

    pub fn deinit(self: *Journal) void {
        self.transaction_indices_by_id.deinit();
        self.account_ids_by_name.deinit();

        for (self.transactions.items) |*transaction| {
            if (transaction.narration) |narration| self.allocator.free(narration);
            if (transaction.id) |id| self.allocator.free(id);
            if (transaction.note) |note| self.allocator.free(note);
            for (transaction.tags.items) |tag| self.allocator.free(tag);

            transaction.tags.deinit(self.allocator);
            transaction.postings.deinit(self.allocator);
        }

        self.transactions.deinit(self.allocator);

        for (self.accounts.items) |account| self.allocator.free(account.name);
        self.accounts.deinit(self.allocator);

        self.catalog.deinit();
        self.allocator.free(self.name);

        self.* = undefined;
    }

    // getters
    pub fn accountIndexFromName(self: *const Journal, name: []const u8) ?AccountIndex {
        return self.account_indices_by_name.get(name);
    }

    pub fn accountFromIndex(self: *const Journal, idx: AccountIndex) ?Account {
        const index = std.math.cast(usize, idx) orelse return null;
        if (index >= self.accounts.items.len) return null;
        return self.accounts.items[index];
    }

    pub fn transactionIndexFromId(self: *const Journal, id: []const u8) ?TransactionIndex {
        return self.transaction_indices_by_id.get(id);
    }

    // adding to journal
    pub fn addAccount(self: *Journal, name: []const u8) !AccountIndex {
        return self.addAccountWithCommodity(name, null);
    }

    pub fn addAccountWithCommodity(
        self: *Journal,
        name: []const u8,
        commodity: ?core.CommodityId,
    ) !AccountIndex {
        if (!isValidAccountName(name)) return error.InvalidAccountName;

        const root_end = std.mem.findScalar(u8, name, ':') orelse name.len;
        const account_type = std.meta.stringToEnum(AccountType, name[0..root_end]) orelse
            return error.InvalidAccountName;

        if (self.account_indices_by_name.contains(name)) return error.DuplicateAccount;
        if (commodity) |commodity_id| {
            if (self.catalog.commodityFromId(commodity_id) == null) return error.UnknownCommodity;
        }
        if (self.accounts.items.len > std.math.maxInt(AccountIndex)) return error.TooManyAccounts;

        try self.accounts.ensureUnusedCapacity(self.allocator, 1);
        try self.account_indices_by_name.ensureUnusedCapacity(1);

        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        const index: AccountIndex = @intCast(self.accounts.items.len);

        self.accounts.appendAssumeCapacity(.{
            .name = owned_name,
            .account_type = account_type,
            .commodity = commodity,
        });
        self.account_indices_by_name.putAssumeCapacityNoClobber(owned_name, index);

        return index;
    }

    pub fn addTransaction(self: *Journal, transaction: NewTransaction) !TransactionIndex {
        if (transaction.id) |id| {
            if (id.len == 0) return error.InvalidTransactionId;
            if (self.transaction_indices_by_id.contains(id)) return error.DuplicateTransactionId;
        }
        if (transaction.note) |note| {
            if (note.len == 0) return error.InvalidTransactionNote;
        }
        if (self.transactions.items.len > std.math.maxInt(TransactionIndex)) {
            return error.TooManyTransactions;
        }

        try self.transactions.ensureUnusedCapacity(self.allocator, 1);
        if (transaction.id != null) {
            try self.transaction_indices_by_id.ensureUnusedCapacity(1);
        }

        var owned_narration: ?[]u8 = null;
        var owned_id: ?[]u8 = null;
        var owned_note: ?[]u8 = null;
        errdefer if (owned_narration) |narration| self.allocator.free(narration);
        errdefer if (owned_id) |id| self.allocator.free(id);
        errdefer if (owned_note) |note| self.allocator.free(note);
        if (transaction.narration) |narration| {
            owned_narration = try self.allocator.dupe(u8, narration);
        }
        if (transaction.id) |id| {
            owned_id = try self.allocator.dupe(u8, id);
        }
        if (transaction.note) |note| {
            owned_note = try self.allocator.dupe(u8, note);
        }

        const index: TransactionIndex = @intCast(self.transactions.items.len);
        self.transactions.appendAssumeCapacity(.{
            .date = transaction.date,
            .narration = owned_narration,
            .id = owned_id,
            .note = owned_note,
            .tags = .empty,
            .postings = .empty,
        });
        if (owned_id) |id| self.transaction_indices_by_id.putAssumeCapacityNoClobber(id, index);

        return index;
    }

    pub fn addTransactionTag(self: *Journal, transaction_index: TransactionIndex, tag: []const u8) !void {
        const index = std.math.cast(usize, transaction_index) orelse return error.UnknownTransaction;

        if (index >= self.transactions.items.len) return error.UnknownTransaction;
        if (!isValidTag(tag)) return error.InvalidTransactionTag;

        const transaction = &self.transactions.items[index];
        for (transaction.tags.items) |existing| {
            if (std.mem.eql(u8, existing, tag)) return error.DuplicateTransactionTag;
        }

        const owned = try self.allocator.dupe(u8, tag);
        errdefer self.allocator.free(owned);

        try transaction.tags.append(self.allocator, owned);
    }

    pub fn addPosting(self: *Journal, transaction_index: TransactionIndex, new_posting: NewPosting) !void {
        // validate
        const index = std.math.cast(usize, transaction_index) orelse return error.UnknownTransaction;
        if (index >= self.transactions.items.len) return error.UnknownTransaction;
        const account = self.accountFromIndex(new_posting.account) orelse return error.UnknownAccount;
        if (self.catalog.commodityFromId(new_posting.amount.commodity) == null) {
            return error.UnknownCommodity;
        }
        if (account.commodity) |commodity| {
            if (commodity != new_posting.amount.commodity) {
                return error.AccountCommodityMismatch;
            }
        }
        if (new_posting.amount.value <= 0) return error.InvalidPostingAmount;
        if (new_posting.valuation) |valuation| {
            if (self.catalog.commodityFromId(valuation.commodity) == null) return error.UnknownCommodity;
            if (valuation.value <= 0) return error.InvalidPostingValuation;
            if (valuation.commodity == new_posting.amount.commodity) return error.RedundantPostingValuation;
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

    // VALIDATIONS

    pub fn validateJournal(self: *const Journal) !void {
        if (self.version != 1) return error.UnsupportedVersion;
        if (self.name.len == 0) return error.EmptyJournalName;

        for (0..self.transactions.items.len) |index| {
            try self.validateTransaction(@intCast(index));
        }
    }

    pub fn validateTransaction(self: *const Journal, transaction_index: TransactionIndex) !void {
        const index = std.math.cast(usize, transaction_index) orelse return error.UnknownTransaction;
        if (index >= self.transactions.items.len) return error.UnknownTransaction;
        const transaction = self.transactions.items[index];
        if (transaction.postings.items.len < 2) return error.TooFewPostings;

        const first_posting = transaction.postings.items[0];
        const expected_commodity =
            if (first_posting.valuation) |valuation|
                valuation.commodity
            else
                first_posting.amount.commodity;

        var debit_total: i64 = 0;
        var credit_total: i64 = 0;

        for (transaction.postings.items) |posting| {
            const amount = posting.valuation orelse posting.amount;
            if (amount.commodity != expected_commodity) return error.MultipleCommodities;

            switch (posting.direction) {
                .debit => {
                    debit_total = std.math.add(i64, debit_total, amount.value) catch
                        return error.TransactionTotalOverflow;
                },
                .credit => {
                    credit_total = std.math.add(i64, credit_total, amount.value) catch
                        return error.TransactionTotalOverflow;
                },
            }
        }

        if (debit_total != credit_total) {
            return error.UnbalancedTransaction;
        }
    }
};

// === PUBLIC VALIDATORS

pub fn isValidAccountPrefix(prefix: []const u8) bool {
    if (!isValidAccountName(prefix)) return false;
    const root_end = std.mem.findScalar(u8, prefix, ':') orelse prefix.len;
    return std.meta.stringToEnum(AccountType, prefix[0..root_end]) != null;
}

pub fn matchesAccountPrefix(name: []const u8, prefix: []const u8) bool {
    if (std.mem.eql(u8, name, prefix)) return true;

    return name.len > prefix.len and std.mem.startsWith(u8, name, prefix) and name[prefix.len] == ':';
}

// === PRIVATE

fn isValidAccountName(name: []const u8) bool {
    if (name.len == 0) return false;

    var at_component_start = true;
    var component_ends_with_alphanumeric = false;

    for (name) |char| {
        if (char == ':') {
            if (at_component_start or !component_ends_with_alphanumeric) return false;

            at_component_start = true;
            component_ends_with_alphanumeric = false;
            continue;
        }

        const is_lowercase_letter = char >= 'a' and char <= 'z';
        const is_digit = char >= '0' and char <= '9';

        if (at_component_start) {
            if (!is_lowercase_letter and !is_digit) return false;

            at_component_start = false;
            component_ends_with_alphanumeric = true;
            continue;
        }

        if (!is_lowercase_letter and !is_digit and char != '-' and char != '_') return false;

        component_ends_with_alphanumeric = is_lowercase_letter or is_digit;
    }

    return !at_component_start and component_ends_with_alphanumeric;
}

fn isValidTag(tag: []const u8) bool {
    if (tag.len == 0 or tag[0] < 'a' or tag[0] > 'z') return false;

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
