const std = @import("std");

const decoder = @import("decoder.zig");
const lexer = @import("lang/lexer.zig");
const loader = @import("loader.zig");
const parser = @import("lang/parser.zig");
const source = @import("lang/source.zig");
const source_manager = @import("source_manager.zig");

pub const DiagnosticError = error{
    UnknownSource,
};

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

pub fn writeFromManager(
    writer: *std.Io.Writer,
    manager: *const source_manager.SourceManager,
    diagnostic: Diagnostic,
) !void {
    const file = manager.get(diagnostic.span.source_id) orelse return error.UnknownSource;

    try write(writer, file.path, file.text, diagnostic);
}

pub fn fromDecoderFailure(failure: decoder.Failure) Diagnostic {
    return .{
        .message = switch (failure.kind) {
            .invalid_version => "invalid journal version",
            .unsupported_version => "unsupported journal version",
            .empty_journal_name => "journal name cannot be empty",

            .source_requires_workspace => "journal sources require workspace loading",
            .journal_name_mismatch => "source belongs to a different journal",
            .nested_sources_not_allowed => "only the root journal may declare sources",
            .account_source_contains_other => "account source cannot contain other statements",
            .transaction_source_contains_other => "transaction source cannot contain other statements",

            .invalid_account_prefix => "invalid account type prefix",
            .invalid_account_name => "invalid account name",
            .duplicate_account => "account is declared more than once",
            .too_many_accounts => "journal contains too many accounts",

            .invalid_date => "invalid transaction date",
            .invalid_transaction_id => "invalid transaction ID",
            .invalid_transaction_note => "transaction note cannot be empty",
            .invalid_transaction_tag => "invalid transaction tag",
            .duplicate_transaction_field => "transaction field appears more than once",
            .duplicate_transaction_id => "transaction ID is already in use",
            .duplicate_transaction_tag => "transaction tag appears more than once",
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

pub fn fromLexerFailure(failure: lexer.Failure) Diagnostic {
    return .{
        .message = switch (failure.kind) {
            .unterminated_string => "unterminated string",
            .newline_in_string => "strings cannot contain newlines",
        },
        .span = failure.span,
    };
}

pub fn fromParserFailure(failure: parser.Failure) Diagnostic {
    return .{
        .message = switch (failure.expected) {
            .kind => |kind| switch (kind) {
                .word => "expected a word",
                .string => "expected a quoted string",
                .left_brace => "expected '{'",
                .right_brace => "expected '}'",
                .eof => "expected end of file",
            },
            .word => |word| expectedWordMessage(word),
            .source_role => "expected 'accounts' or 'transactions'",
            .commodity_kind => "expected 'currency', 'security', or 'custom'",
        },
        .span = failure.token.span,
    };
}

pub fn fromLoadFailure(failure: loader.Failure) Diagnostic {
    return switch (failure) {
        .lexer => |value| fromLexerFailure(value),
        .parser => |value| fromParserFailure(value),
        .decoder => |value| fromDecoderFailure(value),
    };
}

fn expectedWordMessage(word: []const u8) []const u8 {
    if (std.mem.eql(u8, word, "meta")) return "expected 'meta'";
    if (std.mem.eql(u8, word, "version")) return "expected 'version'";
    if (std.mem.eql(u8, word, "journal")) return "expected 'journal'";
    if (std.mem.eql(u8, word, "account")) return "expected 'account'";
    if (std.mem.eql(u8, word, "transaction")) return "expected 'transaction'";

    return "expected a keyword";
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

test "map parser failure" {
    var parser_instance = parser.Parser.init(
        \\meta journal "personal"
    );

    try std.testing.expectError(error.UnexpectedToken, parser_instance.parse(std.testing.allocator));

    const diagnostic = fromParserFailure(parser_instance.failure.?);

    try std.testing.expectEqualStrings("expected 'version'", diagnostic.message);
    try std.testing.expectEqual(@as(usize, 1), diagnostic.span.start.line);
}

test "render diagnostic from source manager" {
    var manager = source_manager.SourceManager.init(std.testing.allocator);
    defer manager.deinit();

    _ = try manager.add("journal.fiscus", "meta version 1");

    const accounts = try manager.add("accounts.fiscus", "account mystery:other");

    const diagnostic = Diagnostic{
        .message = "invalid account prefix",
        .span = .{
            .source_id = accounts,
            .start = .{
                .offset = 8,
                .line = 1,
                .column = 9,
            },
            .end = .{
                .offset = 21,
                .line = 1,
                .column = 22,
            },
        },
    };

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    try writeFromManager(&output.writer, &manager, diagnostic);

    try std.testing.expectEqualStrings(
        \\accounts.fiscus:1:9: [error] invalid account prefix
        \\  account mystery:other
        \\          ^^^^^^^^^^^^^
        \\
    , output.written());
}
