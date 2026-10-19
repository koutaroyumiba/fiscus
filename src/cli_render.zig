const std = @import("std");
const fiscus = @import("fiscus");

pub fn writeBalances(
    writer: *std.Io.Writer,
    journal: *const fiscus.accounting.Journal,
    report: *const fiscus.reports.BalanceReport,
) !void {
    for (report.balances.items) |balance| {
        const account = journal.getAccount(balance.account).?;

        try writer.print("{s:<45} ", .{account.name});
        try journal.catalog.writeAmount(writer, balance.amount);
        try writer.writeByte('\n');
    }
}

pub fn writePrefixBalances(
    writer: *std.Io.Writer,
    journal: *const fiscus.accounting.Journal,
    prefix: []const u8,
    report: *const fiscus.reports.PrefixBalanceReport,
) !void {
    for (report.amounts.items, 0..) |amount, amount_index| {
        if (amount_index != 0) {
            try writer.writeByte('\n');
        }

        try writer.print("{s:<45} ", .{prefix});
        try journal.catalog.writeAmount(writer, amount);
        try writer.writeByte('\n');
        try writer.writeAll("------------------------------------------------------------\n");

        for (report.balances.items) |balance| {
            if (balance.amount.commodity != amount.commodity) {
                continue;
            }

            const account = journal.getAccount(balance.account).?;
            try writer.print("  {s:<43} ", .{account.name});
            try journal.catalog.writeAmount(writer, balance.amount);
            try writer.writeByte('\n');
        }
    }
}

pub fn writeInspect(
    writer: *std.Io.Writer,
    journal: *const fiscus.accounting.Journal,
    report: *const fiscus.reports.InspectReport,
) !void {
    for (report.transactions.items, 0..) |transaction_index, report_index| {
        if (report_index != 0) {
            try writer.writeByte('\n');
        }

        const transaction = journal.transactions.items[transaction_index];
        const date = transaction.date.toIsoString();
        try writer.print("txn {s}", .{date[0..]});
        if (transaction.narration) |narration| {
            try writer.print(" \"{s}\"", .{narration});
        }
        try writer.writeAll(" {\n");

        if (transaction.id) |id| {
            try writer.print("    id {s}\n", .{id});
        }
        if (transaction.note) |note| {
            try writer.print("    note \"{s}\"\n", .{note});
        }
        for (transaction.tags.items) |tag| {
            try writer.print("    tag {s}\n", .{tag});
        }

        if (transaction.id != null or transaction.note != null or transaction.tags.items.len != 0) {
            try writer.writeByte('\n');
        }

        for (transaction.postings.items) |posting| {
            const marker: u8 = switch (posting.direction) {
                .debit => '+',
                .credit => '-',
            };
            const account = journal.getAccount(posting.account).?;

            try writer.print("    {c} {s} ", .{ marker, account.name });
            try journal.catalog.writeAmount(writer, posting.amount);
            if (posting.valuation) |valuation| {
                try writer.writeAll(" @@ ");
                try journal.catalog.writeAmount(writer, valuation);
            }
            try writer.writeByte('\n');
        }

        try writer.writeAll("}\n");
    }
}

pub fn writeAccountRegister(
    writer: *std.Io.Writer,
    journal: *const fiscus.accounting.Journal,
    report: *const fiscus.reports.AccountRegisterReport,
) !void {
    var entry_index: usize = 0;
    while (entry_index < report.entries.items.len) {
        if (entry_index != 0) {
            try writer.writeByte('\n');
        }

        const transaction_index = report.entries.items[entry_index].transaction;
        const transaction = journal.transactions.items[transaction_index];
        const date = transaction.date.toIsoString();
        try writer.print("{s}", .{date[0..]});
        if (transaction.narration) |narration| {
            try writer.print("  {s}", .{narration});
        }
        try writer.writeByte('\n');

        while (entry_index < report.entries.items.len and
            report.entries.items[entry_index].transaction == transaction_index)
        {
            const entry = report.entries.items[entry_index];

            try writer.writeAll("    change   ");
            if (entry.change.value > 0) {
                try writer.writeByte('+');
            }
            try journal.catalog.writeAmount(writer, entry.change);
            try writer.writeByte('\n');

            try writer.writeAll("    balance  ");
            try journal.catalog.writeAmount(writer, entry.balance);
            try writer.writeByte('\n');

            entry_index += 1;
        }
    }
}

test "render inspected transaction in canonical form" {
    var journal = try fiscus.accounting.Journal.init(std.testing.allocator, 1, "personal");
    defer journal.deinit();

    const bank = try journal.addAccount("asset:bank");
    const income = try journal.addAccount("income:salary");
    const amount = try journal.catalog.parseAmount("100.00", "AUD");
    const transaction = try journal.addTransaction(.{
        .date = try fiscus.core.Date.parse("2026-01-15"),
        .id = "salary-1",
        .narration = "Salary",
        .note = "Monthly pay",
    });
    try journal.addTransactionTag(transaction, "income");
    try journal.addPosting(transaction, .{ .direction = .debit, .account = bank, .amount = amount });
    try journal.addPosting(transaction, .{ .direction = .credit, .account = income, .amount = amount });

    var report = try fiscus.reports.inspectTransactions(std.testing.allocator, &journal, .{});
    defer report.deinit();

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try writeInspect(&output.writer, &journal, &report);

    try std.testing.expectEqualStrings(
        \\txn 2026-01-15 "Salary" {
        \\    id salary-1
        \\    note "Monthly pay"
        \\    tag income
        \\
        \\    + asset:bank 100.00 AUD
        \\    - income:salary 100.00 AUD
        \\}
        \\
    , output.written());

    var account_register = try fiscus.reports.calculateAccountRegister(
        std.testing.allocator,
        &journal,
        bank,
        .{},
    );
    defer account_register.deinit();

    var register_output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer register_output.deinit();
    try writeAccountRegister(&register_output.writer, &journal, &account_register);

    try std.testing.expectEqualStrings(
        \\2026-01-15  Salary
        \\    change   +100.00 AUD
        \\    balance  100.00 AUD
        \\
    , register_output.written());
}
