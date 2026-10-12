const std = @import("std");

const accounting = @import("accounting.zig");
const ast = @import("lang/ast.zig");
const source = @import("lang/source.zig");
const time = @import("time.zig");

pub const FailureKind = enum {
    invalid_version,
    unsupported_version,
    empty_journal_name,

    source_requires_workspace,
    journal_name_mismatch,
    nested_sources_not_allowed,
    account_source_contains_other,
    transaction_source_contains_other,

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

pub const SourceDocument = struct {
    role: ast.SourceRole,
    document: *const ast.Document,
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

    pub fn createJournal(self: *Self, document: *const ast.Document) !accounting.Journal {
        self.failure = null;

        const version = try self.decodeVersion(document);
        if (document.journal_name.lexeme.len == 0) {
            return self.fail(.empty_journal_name, document.journal_name.span);
        }

        return accounting.Journal.init(self.allocator, version, document.journal_name.lexeme);
    }

    pub fn decode(self: *Self, document: *const ast.Document) !accounting.Journal {
        var journal = try self.createJournal(document);
        errdefer journal.deinit();

        if (document.sources.items.len != 0) {
            return self.fail(.source_requires_workspace, document.sources.items[0].span);
        }

        try self.decodeAccounts(&journal, document.accounts.items);
        try self.decodeTransactions(&journal, document.transactions.items);

        return journal;
    }

    pub fn decodeAccounts(self: *Self, journal: *accounting.Journal, accounts: []const ast.AccountStmt) !void {
        for (accounts) |account| {
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
    }

    pub fn decodeTransactions(
        self: *Self,
        journal: *accounting.Journal,
        transactions: []const ast.TransactionStmt,
    ) !void {
        for (transactions) |transaction| {
            try self.decodeTransaction(journal, transaction);
        }
    }

    pub fn validateSource(
        self: *Self,
        journal: *const accounting.Journal,
        document: *const ast.Document,
        role: ast.SourceRole,
    ) !void {
        _ = try self.decodeVersion(document);

        if (!std.mem.eql(u8, journal.name, document.journal_name.lexeme)) {
            return self.fail(.journal_name_mismatch, document.journal_name.span);
        }

        if (document.sources.items.len != 0) {
            return self.fail(.nested_sources_not_allowed, document.sources.items[0].span);
        }

        switch (role) {
            .accounts => {
                if (document.transactions.items.len != 0) {
                    return self.fail(.account_source_contains_other, document.transactions.items[0].span);
                }
            },
            .transactions => {
                if (document.accounts.items.len != 0) {
                    return self.fail(.transaction_source_contains_other, document.accounts.items[0].span);
                }
            },
        }
    }

    pub fn decodeWorkspace(
        self: *Self,
        root: *const ast.Document,
        sources: []const SourceDocument,
    ) !accounting.Journal {
        var journal = try self.createJournal(root);
        errdefer journal.deinit();

        for (sources) |source_document| {
            try self.validateSource(&journal, source_document.document, source_document.role);
        }

        try self.decodeAccounts(&journal, root.accounts.items);
        for (sources) |source_document| {
            if (source_document.role == .accounts) {
                try self.decodeAccounts(&journal, source_document.document.accounts.items);
            }
        }

        try self.decodeTransactions(&journal, root.transactions.items);
        for (sources) |source_document| {
            if (source_document.role == .transactions) {
                try self.decodeTransactions(&journal, source_document.document.transactions.items);
            }
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

    fn decodeVersion(self: *Self, document: *const ast.Document) DecodeError!u32 {
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
