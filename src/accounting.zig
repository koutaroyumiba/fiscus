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
};
