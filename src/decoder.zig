const std = @import("std");

const accounting = @import("accounting.zig");
const ast = @import("lang/ast.zig");
const source = @import("lang/source.zig");
const time = @import("time.zig");

pub const FailureKind = enum {
    invalid_version,
    unsupported_version,
    empty_journal_name,

    invalid_account_prefix,
    invalid_account_name,
    duplicate_account,
    too_many_accounts,

    invalid_date,
    invalid_transaction_id,
    duplicate_transaction_id,
    too_many_transactions,

    unknown_account,
    unknown_commodity,
    invalid_amount,
    invalid_posting_amount,

    too_few_postings,
    multiple_commodities,
    transaction_total_overflow,
    unbalanced_transaction,
};

pub const Failure = struct {
    kind: FailureKind,
    span: source.Span,
};

pub const DecodeError = error{
    InvalidDocument,
};

pub const Decoder = struct {
    allocator: std.mem.Allocator,
    failure: ?Failure,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .failure = null,
        };
    }

    pub fn decode(self: *Self, document: *const ast.Document) !accounting.Journal {
        self.failure = null;

        const version = try self.parseVersion(document);
        if (document.journal_name.lexeme.len == 0) {
            return self.fail(.empty_journal_name, document.journal_name.span);
        }

        var journal = try accounting.Journal.init(
            self.allocator,
            version,
            document.journal_name.lexeme,
        );
        errdefer journal.deinit();

        for (document.accounts.items) |account| {
            _ = try self.inferAccountType(account);

            _ = journal.addAccount(account.name.lexeme) catch |err| {
                return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.InvalidAccountName => self.fail(.invalid_account_name, account.name.span),
                    error.DuplicateAccount => self.fail(.duplicate_account, account.name.span),
                    error.TooManyAccounts => self.fail(.too_many_accounts, account.name.span),
                };
            };
        }

        for (document.transactions.items) |transaction| {
            try self.decodeTransaction(&journal, transaction);
        }

        return journal;
    }

    fn fail(self: *Self, kind: FailureKind, span: source.Span) DecodeError {
        self.failure = .{
            .kind = kind,
            .span = span,
        };

        return error.InvalidDocument;
    }

    fn parseVersion(self: *Self, document: *const ast.Document) DecodeError!u32 {
        const version = std.fmt.parseInt(u32, document.version.lexeme, 10) catch {
            return self.fail(.invalid_version, document.version.span);
        };

        if (version != 1) {
            return self.fail(.unsupported_version, document.version.span);
        }

        return version;
    }

    fn inferAccountType(self: *Self, account: ast.AccountStmt) DecodeError!accounting.AccountType {
        const name = account.name.lexeme;

        const separator = std.mem.indexOfScalar(u8, name, ':') orelse name.len;
        const root = name[0..separator];

        if (std.mem.eql(u8, root, "asset")) return .asset;
        if (std.mem.eql(u8, root, "liability")) return .liability;
        if (std.mem.eql(u8, root, "equity")) return .equity;
        if (std.mem.eql(u8, root, "income")) return .income;
        if (std.mem.eql(u8, root, "expense")) return .expense;

        return self.fail(.invalid_account_prefix, account.name.span);
    }

    fn decodeTransaction(self: *Self, journal: *accounting.Journal, transaction: ast.TransactionStmt) !void {
        const date = time.Date.parse(transaction.date.lexeme) catch {
            return self.fail(.invalid_date, transaction.date.span);
        };

        const external_id = if (transaction.external_id) |id| id.lexeme else null;
        const transaction_index = journal.addTransaction(external_id, date, transaction.description.lexeme) catch |err| {
            const id_span = if (transaction.external_id) |id| id.span else transaction.span;
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InvalidTransactionId => self.fail(.invalid_transaction_id, id_span),
                error.DuplicateTransactionId => self.fail(.duplicate_transaction_id, id_span),
                error.TooManyTransactions => self.fail(.too_many_transactions, transaction.span),
            };
        };

        for (transaction.postings.items) |posting| {
            try self.decodePosting(journal, transaction_index, posting);
        }

        journal.validateTransaction(transaction_index) catch |err| {
            return switch (err) {
                error.TooFewPostings => self.fail(.too_few_postings, transaction.span),
                error.MultipleCommodities => self.fail(.multiple_commodities, transaction.span),
                error.TransactionTotalOverflow => self.fail(.transaction_total_overflow, transaction.span),
                error.UnbalancedTransaction => self.fail(.unbalanced_transaction, transaction.span),
                error.UnknownTransaction => unreachable,
            };
        };
    }

    fn decodePosting(
        self: *Self,
        journal: *accounting.Journal,
        transaction_index: accounting.TransactionIndex,
        posting: ast.PostingStmt,
    ) !void {
        const account = journal.findAccount(posting.account.lexeme) orelse {
            return self.fail(.unknown_account, posting.account.span);
        };

        const amount = journal.catalog.parseAmount(posting.amount.lexeme, posting.commodity.lexeme) catch |err| {
            return switch (err) {
                error.UnknownCommodity => self.fail(.unknown_commodity, posting.commodity.span),
                error.InvalidAmount,
                error.TooMuchPrecision,
                error.Overflow,
                => self.fail(.invalid_amount, posting.amount.span),
            };
        };

        // i dont really like this...
        // TODO: need to implement a cleaner solution here
        const direction: accounting.Direction = switch (posting.direction) {
            .debit => .debit,
            .credit => .credit,
        };

        journal.addPosting(transaction_index, direction, account, amount) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InvalidPostingAmount => self.fail(.invalid_posting_amount, posting.amount.span),

                // we should have already checked for these
                error.UnknownAccount,
                error.UnknownCommodity,
                error.UnknownTransaction,
                => unreachable,
            };
        };
    }
};
