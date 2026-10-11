const std = @import("std");

const decoder = @import("decoder.zig");
const source = @import("lang/source.zig");

pub const Diagnostic = struct {
    message: []const u8,
    span: source.Span,
};

pub fn write(
    writer: *std.Io.Writer,
    file_name: []const u8,
    input: []const u8,
    diagnostic: Diagnostic,
) !void {
    const location = diagnostic.span.start;
    const offset = @min(location.offset, input.len);

    var line_start = offset;
    while (line_start > 0 and input[line_start - 1] != '\n') {
        line_start -= 1;
    }

    var line_end = offset;
    while (line_end < input.len and input[line_end] != '\n' and input[line_end] != '\r') {
        line_end += 1;
    }

    try writer.print("{s}:{d}:{d}: [error] {s}\n", .{ file_name, location.line, location.column, diagnostic.message });

    try writer.print("  {s}\n  ", .{input[line_start..line_end]});

    for (input[line_start..offset]) |char| {
        try writer.writeByte(if (char == '\t') '\t' else ' ');
    }

    var highlight_end = @min(diagnostic.span.end.offset, line_end);
    if (highlight_end <= offset) {
        highlight_end = @min(offset + 1, line_end);
    }

    const highlight_length = @max(@as(usize, 1), highlight_end - offset);
    for (0..highlight_length) |_| {
        try writer.writeByte('^');
    }
    try writer.writeByte('\n');
}

pub fn fromDecoderFailure(failure: decoder.Failure) Diagnostic {
    return .{
        .message = switch (failure.kind) {
            .invalid_version => "invalid journal version",
            .unsupported_version => "unsupported journal version",
            .empty_journal_name => "journal name cannot be empty",

            .invalid_account_prefix => "invalid account type prefix",
            .invalid_account_name => "invalid account name",
            .duplicate_account => "account is declared more than once",
            .too_many_accounts => "journal contains too many accounts",

            .invalid_date => "invalid transaction date",
            .invalid_transaction_id => "invalid transaction ID",
            .duplicate_transaction_id => "transaction ID is already in use",
            .too_many_transactions => "journal contains too many transactions",

            .unknown_account => "posting references an unknown account",
            .unknown_commodity => "posting uses an unknown commodity",
            .invalid_amount => "invalid posting amount",
            .invalid_posting_amount => "posting amount must be greater than zero",

            .too_few_postings => "transaction must contain at least two postings",
            .multiple_commodities => "transaction contains multiple commodities",
            .transaction_total_overflow => "transaction total is too large",
            .unbalanced_transaction => "transaction debits and credits do not balance",
        },
        .span = failure.span,
    };
}

test "render source diagnostic" {
    const input =
        \\account asset:bank
        \\account mystery:other
    ;

    const diagnostic = Diagnostic{
        .message = "invalid account prefix",
        .span = .{
            .start = .{
                .offset = 27,
                .line = 2,
                .column = 9,
            },
            .end = .{
                .offset = 34,
                .line = 2,
                .column = 16,
            },
        },
    };

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    try write(&output.writer, "journal.fiscus", input, diagnostic);

    try std.testing.expectEqualStrings(
        \\journal.fiscus:2:9: [error] invalid account prefix
        \\  account mystery:other
        \\          ^^^^^^^
        \\
    , output.written());
}
