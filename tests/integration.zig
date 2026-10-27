const std = @import("std");
const fiscus = @import("fiscus");

test "parse and decode complete journal" {
    const input =
        \\meta version 1
        \\meta journal "personal"
        \\
        \\account asset:bank
        \\account equity:opening-balances
        \\account expense:groceries
        \\
        \\transaction 2026-01-01 "Opening balance" {
        \\  debit asset:bank 1000.00 AUD
        \\  credit equity:opening-balances 1000.00 AUD
        \\}
        \\
        \\transaction 2026-01-17 "Groceries" {
        \\  debit expense:groceries 82.40 AUD
        \\  credit equity:opening-balances 82.40 AUD
        \\}
    ;

    var result = try fiscus.loader.load(std.testing.allocator, input);
    defer result.deinit();

    switch (result) {
        .journal => |journal| {
            try std.testing.expectEqualStrings("personal", journal.name);
            try std.testing.expectEqual(@as(usize, 3), journal.accounts.items.len);
            try std.testing.expectEqual(@as(usize, 2), journal.transactions.items.len);

            try journal.validateJournal();
        },
        .failure => return error.UnexpectedFailure,
    }
}

test "decode fixed account commodities and short transactions" {
    const input =
        \\meta version 1
        \\meta journal "personal"
        \\
        \\account asset:bank commodity NZD
        \\account expense:groceries commodity NZD
        \\
        \\txn 2026-01-17 "Groceries" {
        \\  + expense:groceries 82.40
        \\  - asset:bank 82.40
        \\}
    ;

    var result = try fiscus.loader.load(std.testing.allocator, input);
    defer result.deinit();

    switch (result) {
        .journal => |journal| {
            const nzd = journal.catalog.idFromSymbol("NZD") orelse return error.ExpectedCommodity;
            try std.testing.expectEqual(nzd, journal.accounts.items[0].commodity.?);
            try std.testing.expectEqual(nzd, journal.transactions.items[0].postings.items[0].amount.commodity);
            try std.testing.expectEqual(fiscus.ledger.Direction.debit, journal.transactions.items[0].postings.items[0].direction);
            try std.testing.expectEqual(fiscus.ledger.Direction.credit, journal.transactions.items[0].postings.items[1].direction);
            try journal.validateJournal();
        },
        .failure => return error.UnexpectedFailure,
    }
}

test "reject unknown fixed account commodity" {
    const input =
        \\meta version 1
        \\meta journal "personal"
        \\
        \\account asset:bank commodity CAD
    ;

    try expectDecoderFailure(input, .unknown_account_commodity);
}

test "require posting commodity for unrestricted account" {
    const input =
        \\meta version 1
        \\meta journal "personal"
        \\
        \\account asset:bank
        \\account equity:opening-balances commodity NZD
        \\
        \\txn 2026-01-01 {
        \\  debit asset:bank 100.00
        \\  credit equity:opening-balances 100.00
        \\}
    ;

    try expectDecoderFailure(input, .missing_posting_commodity);
}

test "reject posting commodity that differs from account" {
    const input =
        \\meta version 1
        \\meta journal "personal"
        \\
        \\account asset:bank commodity NZD
        \\account equity:opening-balances commodity NZD
        \\
        \\txn 2026-01-01 {
        \\  debit asset:bank 100.00 AUD
        \\  credit equity:opening-balances 100.00 NZD
        \\}
    ;

    try expectDecoderFailure(input, .account_commodity_mismatch);
}

test "report unknown posting account" {
    const input =
        \\meta version 1
        \\meta journal "personal"
        \\
        \\account asset:bank
        \\
        \\transaction 2026-01-17 "Groceries" {
        \\  debit expense:groceries 82.40 AUD
        \\  credit asset:bank 82.40 AUD
        \\}
    ;

    var result = try fiscus.loader.load(std.testing.allocator, input);
    defer result.deinit();

    switch (result) {
        .failure => |failure| switch (failure) {
            .decoder => |decoder_failure| {
                try std.testing.expectEqual(fiscus.decoder.FailureKind.unknown_account, decoder_failure.kind);
                try std.testing.expectEqual(@as(usize, 7), decoder_failure.span.start.line);
            },
            else => return error.UnexpectedFailureKind,
        },
        .journal => return error.ExpectedFailure,
    }
}

test "reject unbalanced fixture" {
    const input = @embedFile("fixtures/unbalanced.fiscus");
    var result = try fiscus.loader.load(std.testing.allocator, input);
    defer result.deinit();

    switch (result) {
        .failure => |failure| switch (failure) {
            .decoder => |decoder_failure| {
                try std.testing.expectEqual(fiscus.decoder.FailureKind.unbalanced_transaction, decoder_failure.kind);

                const diagnostic = fiscus.diagnostics.fromLoadFailure(failure);
                try std.testing.expectEqualStrings("transaction debits and credits do not balance", diagnostic.message);
            },
            else => return error.UnexpectedFailureKind,
        },
        .journal => return error.ExpectedFailure,
    }
}

test "decode semantic multi-source workspace" {
    const root_text =
        \\meta version 1
        \\meta journal "personal"
        \\
        \\source accounts "accounts.fiscus"
        \\source transactions "transactions.fiscus"
    ;

    const accounts_text =
        \\meta version 1
        \\meta journal "personal"
        \\
        \\account asset:bank
        \\account equity:opening-balances
    ;

    const transactions_text =
        \\meta version 1
        \\meta journal "personal"
        \\
        \\transaction 2026-01-01 "opening balance" {
        \\  debit asset:bank 1000.00 AUD
        \\  credit equity:opening-balances 1000.00 AUD
        \\}
    ;

    var root_parser = fiscus.lang.parser.Parser.initWithSource(0, root_text);
    var root = try root_parser.parse(std.testing.allocator);
    defer root.deinit(std.testing.allocator);

    var accounts_parser = fiscus.lang.parser.Parser.initWithSource(1, accounts_text);
    var accounts = try accounts_parser.parse(std.testing.allocator);
    defer accounts.deinit(std.testing.allocator);

    var transactions_parser = fiscus.lang.parser.Parser.initWithSource(2, transactions_text);
    var transactions = try transactions_parser.parse(std.testing.allocator);
    defer transactions.deinit(std.testing.allocator);

    const source_documents = [_]fiscus.decoder.SourceDocument{ .{
        .role = .accounts,
        .document = &accounts,
    }, .{
        .role = .transactions,
        .document = &transactions,
    } };

    var decoder = fiscus.decoder.Decoder.init(std.testing.allocator);
    var journal = try decoder.decodeWorkspace(&root, &source_documents);
    defer journal.deinit();

    try std.testing.expectEqual(@as(usize, 2), journal.accounts.items.len);
    try std.testing.expectEqual(@as(usize, 1), journal.transactions.items.len);
}

test "decode exact total posting valuation" {
    const input =
        \\meta version 1
        \\meta journal "investments"
        \\
        \\commodity NZX.AIR security scale 6 "Air New Zealand"
        \\
        \\account asset:broker:shares commodity NZX.AIR
        \\account asset:bank commodity NZD
        \\account expense:broker-fees commodity NZD
        \\
        \\txn 2026-02-02 "Buy shares" {
        \\  debit asset:broker:shares 10.000000 @@ 7.80 NZD
        \\  debit expense:broker-fees 1.00
        \\  credit asset:bank 8.80
        \\}
    ;

    var result = try fiscus.loader.load(std.testing.allocator, input);
    defer result.deinit();

    switch (result) {
        .journal => |journal| {
            const posting = journal.transactions.items[0].postings.items[0];

            try std.testing.expectEqualStrings(
                "NZX.AIR",
                journal.catalog.commodityFromId(posting.amount.commodity).?.symbol,
            );
            try std.testing.expectEqual(@as(i64, 10_000_000), posting.amount.value);

            const valuation = posting.valuation.?;
            try std.testing.expectEqualStrings(
                "NZD",
                journal.catalog.commodityFromId(valuation.commodity).?.symbol,
            );
            try std.testing.expectEqual(@as(i64, 780), valuation.value);

            var report = try fiscus.reports.calculateBalances(std.testing.allocator, &journal, .{});
            defer report.deinit();

            try expectBalance(&journal, &report, "asset:broker:shares", "NZX.AIR", "10.000000");
            try expectBalance(&journal, &report, "expense:broker-fees", "NZD", "1.00");
        },
        .failure => return error.UnexpectedFailure,
    }
}

test "report invalid total posting valuations" {
    const Case = struct {
        input: []const u8,
        expected: fiscus.decoder.FailureKind,
    };

    const cases = [_]Case{
        .{
            .input =
            \\meta version 1
            \\meta journal "personal"
            \\
            \\account asset:bank
            \\account equity:opening-balances
            \\
            \\transaction 2026-02-01 {
            \\  debit asset:bank 100.00 AUD @@ 90.00 UNKNOWN
            \\  credit equity:opening-balances 100.00 AUD
            \\}
            ,
            .expected = .unknown_valuation_commodity,
        },
        .{
            .input =
            \\meta version 1
            \\meta journal "personal"
            \\
            \\account asset:bank
            \\account equity:opening-balances
            \\
            \\transaction 2026-02-01 {
            \\  debit asset:bank 100.00 AUD @@ nope NZD
            \\  credit equity:opening-balances 100.00 AUD
            \\}
            ,
            .expected = .invalid_valuation_amount,
        },
        .{
            .input =
            \\meta version 1
            \\meta journal "personal"
            \\
            \\account asset:bank
            \\account equity:opening-balances
            \\
            \\transaction 2026-02-01 {
            \\  debit asset:bank 100.00 AUD @@ 0.00 NZD
            \\  credit equity:opening-balances 100.00 AUD
            \\}
            ,
            .expected = .invalid_posting_valuation,
        },
        .{
            .input =
            \\meta version 1
            \\meta journal "personal"
            \\
            \\account asset:bank
            \\account equity:opening-balances
            \\
            \\transaction 2026-02-01 {
            \\  debit asset:bank 100.00 AUD @@ 100.00 AUD
            \\  credit equity:opening-balances 100.00 AUD
            \\}
            ,
            .expected = .redundant_posting_valuation,
        },
    };

    for (cases) |case| {
        try expectDecoderFailure(case.input, case.expected);
    }
}

test "load activity coverage workspace" {
    var workspace = try fiscus.workspace.load(
        std.testing.allocator,
        std.testing.io,
        std.Io.Dir.cwd(),
        "tests/fixtures/activity-coverage/journal.fiscus",
    );
    defer workspace.deinit();

    switch (workspace.result) {
        .journal => |journal| {
            try std.testing.expectEqualStrings("activity-coverage", journal.name);
            try std.testing.expectEqual(@as(usize, 21), journal.accounts.items.len);
            try std.testing.expectEqual(@as(usize, 25), journal.transactions.items.len);
            try journal.validateJournal();

            const air_id = journal.catalog.idFromSymbol("NZX.AIR") orelse return error.ExpectedCommodity;
            const air = journal.catalog.commodityFromId(air_id).?;
            try std.testing.expectEqual(fiscus.core.CommodityKind.security, air.kind);
            try std.testing.expectEqual(@as(u8, 6), air.scale);
            try std.testing.expectEqualStrings("Air New Zealand", air.name.?);

            var report = try fiscus.reports.calculateBalances(std.testing.allocator, &journal, .{});
            defer report.deinit();

            try std.testing.expectEqual(@as(usize, 21), report.balances.items.len);
            try expectBalance(&journal, &report, "asset:bank:nzd:everyday", "NZD", "6281.20");
            try expectBalance(&journal, &report, "asset:bank:nzd:savings", "NZD", "2500.00");
            try expectBalance(&journal, &report, "asset:bank:aud:everyday", "AUD", "1089.00");
            try expectBalance(&journal, &report, "asset:cash:nzd", "NZD", "170.00");
            try expectBalance(&journal, &report, "asset:broker:nzx:shares", "NZX.AIR", "10.000000");
            try expectBalance(&journal, &report, "liability:credit-card:nzd", "NZD", "250.00");
            try expectBalance(&journal, &report, "liability:loan:nzd", "NZD", "9600.00");
            try expectBalance(&journal, &report, "expense:food:groceries", "NZD", "315.00");
            try expectBalance(&journal, &report, "expense:broker-fees", "NZD", "1.00");
            try expectBalance(&journal, &report, "expense:currency-fees", "AUD", "1.00");
        },
        .failure => return error.UnexpectedFailure,
    }
}

fn expectDecoderFailure(
    input: []const u8,
    expected: fiscus.decoder.FailureKind,
) !void {
    var result = try fiscus.loader.load(std.testing.allocator, input);
    defer result.deinit();

    switch (result) {
        .failure => |failure| switch (failure) {
            .decoder => |decoder_failure| {
                try std.testing.expectEqual(expected, decoder_failure.kind);
            },
            else => return error.UnexpectedFailureKind,
        },
        .journal => return error.ExpectedFailure,
    }
}

fn expectBalance(
    journal: *const fiscus.ledger.Journal,
    report: *const fiscus.reports.BalanceReport,
    account_name: []const u8,
    commodity_symbol: []const u8,
    expected_text: []const u8,
) !void {
    const account_id = journal.accountIndexFromName(account_name) orelse return error.AccountNotFound;
    const expected = try journal.catalog.parseAmount(expected_text, commodity_symbol);

    for (report.balances.items) |balance| {
        if (balance.account == account_id and balance.amount.commodity == expected.commodity) {
            try std.testing.expectEqual(expected.value, balance.amount.value);
            return;
        }
    }

    return error.BalanceNotFound;
}
