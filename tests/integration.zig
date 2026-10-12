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

            try journal.validate();
        },
        .failure => return error.UnexpectedFailure,
    }
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
