const std = @import("std");
const lexer = @import("lexer.zig");
const source = @import("source.zig");

pub const SourceRole = enum {
    accounts,
    transactions,
};

pub const SourceStmt = struct {
    role: SourceRole,
    path: lexer.Token,
    span: source.Span,
};

pub const AccountType = enum {
    asset,
    liability,
    equity,
    income,
    expense,
};

pub const Direction = enum { debit, credit };

pub const AccountStmt = struct {
    name: lexer.Token,
    span: source.Span,
};

pub const PostingStmt = struct {
    direction: Direction,
    account: lexer.Token,
    amount: lexer.Token,
    commodity: lexer.Token,
    span: source.Span,
};

pub const TransactionFieldKind = enum {
    id,
    note,
    tag,
};

pub const TransactionFieldStmt = struct {
    kind: TransactionFieldKind,
    value: lexer.Token,
    span: source.Span,
};

pub const TransactionStmt = struct {
    date: lexer.Token,
    narration: ?lexer.Token,
    fields: std.ArrayList(TransactionFieldStmt),
    postings: std.ArrayList(PostingStmt),
    span: source.Span,
};

pub const Document = struct {
    version: lexer.Token,
    journal_name: lexer.Token,

    sources: std.ArrayList(SourceStmt),
    accounts: std.ArrayList(AccountStmt),
    transactions: std.ArrayList(TransactionStmt),

    const Self = @This();

    pub fn init(version: lexer.Token, journal_name: lexer.Token) Document {
        return .{
            .version = version,
            .journal_name = journal_name,
            .sources = .empty,
            .accounts = .empty,
            .transactions = .empty,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.transactions.items) |*transaction| {
            transaction.postings.deinit(allocator);
            transaction.fields.deinit(allocator);
        }

        self.transactions.deinit(allocator);
        self.accounts.deinit(allocator);
        self.sources.deinit(allocator);
        self.* = undefined;
    }
};
