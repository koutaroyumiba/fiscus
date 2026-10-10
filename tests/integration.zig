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

    var parser = try fiscus.lang.parser.Parser.init(input);
    var document = try parser.parse(std.testing.allocator);
    defer document.deinit(std.testing.allocator);

    var decoder = fiscus.decoder.Decoder.init(std.testing.allocator);

    var journal = try decoder.decode(&document);
    defer journal.deinit();

    try std.testing.expectEqualStrings("personal", journal.name);
    try std.testing.expectEqual(@as(usize, 3), journal.accounts.items.len);
    try std.testing.expectEqual(@as(usize, 2), journal.transactions.items.len);

    try journal.validate();
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

    var parser = try fiscus.lang.parser.Parser.init(input);
    var document = try parser.parse(std.testing.allocator);
    defer document.deinit(std.testing.allocator);

    var decoder = fiscus.decoder.Decoder.init(std.testing.allocator);

    try std.testing.expectError(error.InvalidDocument, decoder.decode(&document));
    try std.testing.expectEqual(fiscus.decoder.FailureKind.unknown_account, decoder.failure.?.kind);
    try std.testing.expectEqual(@as(usize, 7), decoder.failure.?.span.start.line);
}
