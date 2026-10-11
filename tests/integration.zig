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
