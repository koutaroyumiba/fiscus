test "match account prefixes by component" {
    try std.testing.expect(isValidAccountPrefix("asset"));
    try std.testing.expect(isValidAccountPrefix("asset:bank"));
    try std.testing.expect(isValidAccountPrefix("income:2026:stuff"));
    try std.testing.expect(isValidAccountPrefix("asset:bank:1234"));
    try std.testing.expect(!isValidAccountPrefix("assets:bank"));
    try std.testing.expect(!isValidAccountPrefix("asset:Bank"));
    try std.testing.expect(!isValidAccountPrefix("income:-2026"));
    try std.testing.expect(!isValidAccountPrefix("income:_2026"));
    try std.testing.expect(!isValidAccountPrefix("income:2026:stuff-"));
    try std.testing.expect(!isValidAccountPrefix("income:2026:stuff_"));

    try std.testing.expect(matchesAccountPrefix("asset:bank", "asset:bank"));
    try std.testing.expect(matchesAccountPrefix("asset:bank:checking", "asset:bank"));
    try std.testing.expect(!matchesAccountPrefix("asset:banking", "asset:bank"));
    try std.testing.expect(!matchesAccountPrefix("liability:bank", "asset:bank"));
}

test "construct basic journal" {
    var journal = try Journal.init(
        std.testing.allocator,
        1,
        "personal",
    );
    defer journal.deinit();

    const bank = try journal.addAccount("asset:bank");
    const transaction = try journal.addTransaction(.{
        .date = try core.Date.init(2026, .jan, 1),
        .id = "opening",
    });
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
    try std.testing.expectEqual(transaction, journal.findTransactionById("opening").?);
    try std.testing.expectEqual(@as(?TransactionIndex, null), journal.findTransactionById("missing"));

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

    const transaction = try journal.addTransaction(.{ .date = try core.Date.init(2026, .jan, 17), .narration = "Groceries" });

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

    _ = try journal.catalog.addCommodity(.{
        .kind = .security,
        .symbol = "NZX.AIR",
        .scale = 6,
        .name = null,
    });

    const shares = try journal.addAccount("asset:broker:shares");
    const bank = try journal.addAccount("asset:bank");
    const fees = try journal.addAccount("expense:broker-fees");
    const transaction = try journal.addTransaction(.{
        .date = try core.Date.parse("2026-02-02"),
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
        .date = try core.Date.parse("2026-02-01"),
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

    _ = try journal.catalog.addCommodity(.{
        .kind = .security,
        .symbol = "NZX.AIR",
        .scale = 6,
        .name = null,
    });

    const shares = try journal.addAccount("asset:broker:shares");
    const transaction = try journal.addTransaction(.{
        .date = try core.Date.parse("2026-02-02"),
    });
    const quantity = try journal.catalog.parseAmount("10.000000", "NZX.AIR");
    const nzd = journal.catalog.idFromSymbol("NZD").?;

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

    _ = try journal.catalog.addCommodity(.{
        .kind = .security,
        .symbol = "NZX.AIR",
        .scale = 6,
        .name = null,
    });

    const shares = try journal.addAccount("asset:broker:shares");
    const bank = try journal.addAccount("asset:bank");

    const mixed = try journal.addTransaction(.{
        .date = try core.Date.parse("2026-02-01"),
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
        .date = try core.Date.parse("2026-02-02"),
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
