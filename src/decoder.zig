const std = @import("std");

const accounting = @import("accounting.zig");
const ast = @import("lang/ast.zig");
const commodity = @import("commodity.zig");
const source = @import("lang/source.zig");
const time = @import("time.zig");

pub const FailureKind = enum {
    invalid_version,
    unsupported_version,
    empty_journal_name,

    source_requires_workspace,
    journal_name_mismatch,
    nested_sources_not_allowed,
    commodity_source_contains_other,
    account_source_contains_other,
    transaction_source_contains_other,

    invalid_commodity_symbol,
    invalid_commodity_name,
    invalid_commodity_scale,
    duplicate_commodity,
    too_many_commodities,

    invalid_account_prefix,
    invalid_account_name,
    duplicate_account,
    too_many_accounts,

    invalid_date,
    invalid_transaction_id,
    invalid_transaction_note,
    invalid_transaction_tag,
    duplicate_transaction_field,
    duplicate_transaction_id,
    duplicate_transaction_tag,
    too_many_transactions,

    unknown_account,
    unknown_commodity,
    unknown_valuation_commodity,
    invalid_amount,
    invalid_posting_amount,
    invalid_valuation_amount,
    invalid_posting_valuation,
    redundant_posting_valuation,

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

        try self.decodeCommodities(&journal, document.commodities.items);
        try self.decodeAccounts(&journal, document.accounts.items);
        try self.decodeTransactions(&journal, document.transactions.items);

        return journal;
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

        try self.decodeCommodities(&journal, root.commodities.items);
        for (sources) |source_document| {
            if (source_document.role == .commodities) {
                try self.decodeCommodities(&journal, source_document.document.commodities.items);
            }
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

    pub fn decodeCommodities(self: *Self, journal: *accounting.Journal, commodities: []const ast.CommodityStmt) !void {
        for (commodities) |comm| {
            const scale = std.fmt.parseInt(u8, comm.scale.lexeme, 10) catch {
                return self.fail(.invalid_commodity_scale, comm.scale.span);
            };
            const kind: commodity.Kind = switch (comm.kind) {
                .currency => .currency,
                .security => .security,
                .custom => .custom,
            };
            const name = if (comm.name) |token| token.lexeme else null;

            _ = journal.catalog.add(.{
                .symbol = comm.symbol.lexeme,
                .kind = kind,
                .scale = scale,
                .name = name,
            }) catch |err| {
                return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.InvalidSymbol => self.fail(.invalid_commodity_symbol, comm.symbol.span),
                    error.InvalidName => self.fail(.invalid_commodity_name, comm.name.?.span),
                    error.InvalidScale => self.fail(.invalid_commodity_scale, comm.scale.span),
                    error.DuplicateSymbol => self.fail(.duplicate_commodity, comm.symbol.span),
                    error.TooManyCommodities => self.fail(.too_many_commodities, comm.span),
                };
            };
        }
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
            .commodities => {
                if (document.accounts.items.len != 0) {
                    return self.fail(.commodity_source_contains_other, document.accounts.items[0].span);
                }
                if (document.transactions.items.len != 0) {
                    return self.fail(.commodity_source_contains_other, document.transactions.items[0].span);
                }
            },
            .accounts => {
                if (document.commodities.items.len != 0) {
                    return self.fail(.account_source_contains_other, document.commodities.items[0].span);
                }
                if (document.transactions.items.len != 0) {
                    return self.fail(.account_source_contains_other, document.transactions.items[0].span);
                }
            },
            .transactions => {
                if (document.commodities.items.len != 0) {
                    return self.fail(.transaction_source_contains_other, document.commodities.items[0].span);
                }
                if (document.accounts.items.len != 0) {
                    return self.fail(.transaction_source_contains_other, document.accounts.items[0].span);
                }
            },
        }
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
        const narration = if (transaction.narration) |token| token.lexeme else null;

        var id_field: ?ast.TransactionFieldStmt = null;
        var note_field: ?ast.TransactionFieldStmt = null;

        for (transaction.fields.items) |field| {
            switch (field.kind) {
                .id => {
                    if (id_field != null) {
                        return self.fail(.duplicate_transaction_field, field.span);
                    }
                    id_field = field;
                },
                .note => {
                    if (note_field != null) {
                        return self.fail(.duplicate_transaction_field, field.span);
                    }
                    note_field = field;
                },
                .tag => {},
            }
        }

        const id = if (id_field) |field| field.value.lexeme else null;
        const note = if (note_field) |field| field.value.lexeme else null;

        const transaction_index = journal.addTransaction(.{
            .date = date,
            .narration = narration,
            .id = id,
            .note = note,
        }) catch |err| {
            const id_span = if (id_field) |field| field.span else transaction.span;
            const note_span = if (note_field) |field| field.span else transaction.span;
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InvalidTransactionId => self.fail(.invalid_transaction_id, id_span),
                error.InvalidTransactionNote => self.fail(.invalid_transaction_note, note_span),
                error.DuplicateTransactionId => self.fail(.duplicate_transaction_id, id_span),
                error.TooManyTransactions => self.fail(.too_many_transactions, transaction.span),
            };
        };

        for (transaction.fields.items) |field| {
            if (field.kind != .tag) {
                continue;
            }

            journal.addTransactionTag(transaction_index, field.value.lexeme) catch |err| {
                return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.InvalidTransactionTag => self.fail(.invalid_transaction_tag, field.span),
                    error.DuplicateTransactionTag => self.fail(.duplicate_transaction_tag, field.span),
                    error.UnknownTransaction => unreachable,
                };
            };
        }

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
        // i dont really like this...
        // TODO: need to implement a cleaner solution here
        const direction: accounting.Direction = switch (posting.direction) {
            .debit => .debit,
            .credit => .credit,
        };

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

        const valuation: ?commodity.Amount = if (posting.valuation) |expression|
            journal.catalog.parseAmount(expression.amount.lexeme, expression.commodity.lexeme) catch |err| {
                return switch (err) {
                    error.UnknownCommodity => self.fail(.unknown_valuation_commodity, expression.commodity.span),
                    error.InvalidAmount,
                    error.TooMuchPrecision,
                    error.Overflow,
                    => self.fail(.invalid_valuation_amount, expression.amount.span),
                };
            }
        else
            null;

        journal.addPosting(transaction_index, .{
            .direction = direction,
            .account = account,
            .amount = amount,
            .valuation = valuation,
        }) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InvalidPostingAmount => self.fail(.invalid_posting_amount, posting.amount.span),
                error.InvalidPostingValuation => self.fail(.invalid_posting_valuation, posting.valuation.?.span),
                error.RedundantPostingValuation => self.fail(.redundant_posting_valuation, posting.valuation.?.span),

                // we should have already checked for these
                error.UnknownAccount,
                error.UnknownCommodity,
                error.UnknownTransaction,
                => unreachable,
            };
        };
    }
};
