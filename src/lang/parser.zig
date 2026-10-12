const std = @import("std");

const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const source = @import("source.zig");

// crazy use of a tagged union :D
pub const Expected = union(enum) {
    kind: lexer.TokenKind,
    word: []const u8,
    source_role: void,
};

pub const Failure = struct {
    token: lexer.Token,
    expected: Expected,
};

pub const ParserError = error{
    UnexpectedToken,
};

pub const Parser = struct {
    lexer: lexer.Lexer,
    current: ?lexer.Token,
    failure: ?Failure,

    const Self = @This();

    pub fn init(input: []const u8) Self {
        return initWithSource(source.root_source_id, input);
    }

    pub fn initWithSource(source_id: source.SourceId, input: []const u8) Self {
        var tokenizer = lexer.Lexer.initWithSource(source_id, input);

        const current: ?lexer.Token = tokenizer.next() catch null;

        return .{
            .lexer = tokenizer,
            .current = current,
            .failure = null,
        };
    }

    pub fn parse(self: *Self, allocator: std.mem.Allocator) !ast.Document {
        if (self.current == null) {
            return self.currentLexerError();
        }

        _ = try self.expectWord("meta");
        _ = try self.expectWord("version");
        const version = try self.expectKind(.word);

        _ = try self.expectWord("meta");
        _ = try self.expectWord("journal");
        const journal_name = try self.expectKind(.string);

        var document = ast.Document.init(version, journal_name);
        errdefer document.deinit(allocator);

        while (self.matchesWord("source")) {
            const source_statement = try self.parseSource();
            try document.sources.append(allocator, source_statement);
        }

        while (self.matchesWord("account")) {
            const account = try self.parseAccount();
            try document.accounts.append(allocator, account);
        }

        while (self.matchesWord("transaction")) {
            var transaction = try self.parseTransaction(allocator);

            document.transactions.append(allocator, transaction) catch |err| {
                transaction.postings.deinit(allocator);
                return err;
            };
        }

        _ = try self.expectKind(.eof);
        return document;
    }

    fn advance(self: *Self) !lexer.Token {
        const consumed = self.current orelse return self.currentLexerError();
        self.current = try self.lexer.next();
        return consumed;
    }

    fn expectKind(self: *Self, expected: lexer.TokenKind) !lexer.Token {
        const current = self.current orelse return self.currentLexerError();

        if (current.kind != expected) {
            self.failure = .{
                .token = current,
                .expected = .{ .kind = expected },
            };

            return error.UnexpectedToken;
        }

        return self.advance();
    }

    fn expectWord(self: *Self, expected: []const u8) !lexer.Token {
        const current = self.current orelse return self.currentLexerError();

        if (current.kind != .word or !std.mem.eql(u8, current.lexeme, expected)) {
            self.failure = .{
                .token = current,
                .expected = .{ .word = expected },
            };

            return error.UnexpectedToken;
        }

        return self.advance();
    }

    fn matchesWord(self: *const Self, expected: []const u8) bool {
        const current = self.current orelse return false;
        return current.kind == .word and std.mem.eql(u8, current.lexeme, expected);
    }

    fn parseSourceRole(self: *Self) !ast.SourceRole {
        const current = self.current orelse return self.currentLexerError();

        if (current.kind != .word) {
            self.failure = .{
                .token = current,
                .expected = .{ .source_role = {} },
            };

            return error.UnexpectedToken;
        }

        const role: ast.SourceRole =
            if (std.mem.eql(u8, current.lexeme, "accounts"))
                .accounts
            else if (std.mem.eql(u8, current.lexeme, "transactions"))
                .transactions
            else {
                self.failure = .{
                    .token = current,
                    .expected = .{ .source_role = {} },
                };

                return error.UnexpectedToken;
            };

        _ = try self.advance();
        return role;
    }

    fn parseSource(self: *Self) !ast.SourceStmt {
        const keyword = try self.expectWord("source");
        const role = try self.parseSourceRole();
        const path = try self.expectKind(.string);

        return .{
            .role = role,
            .path = path,
            .span = .{
                .source_id = keyword.span.source_id,
                .start = keyword.span.start,
                .end = path.span.end,
            },
        };
    }

    fn parseAccount(self: *Self) !ast.AccountStmt {
        const keyword = try self.expectWord("account");
        const name = try self.expectKind(.word);

        return .{
            .name = name,
            .span = .{
                .source_id = keyword.span.source_id,
                .start = keyword.span.start,
                .end = name.span.end,
            },
        };
    }

    fn parsePosting(self: *Self) !ast.PostingStmt {
        const direction_token = self.current.?;

        const direction: ast.Direction =
            if (self.matchesWord("debit"))
                .debit
            else if (self.matchesWord("credit"))
                .credit
            else
                unreachable;

        _ = try self.advance();

        const account = try self.expectKind(.word);
        const amount = try self.expectKind(.word);
        const commodity = try self.expectKind(.word);

        return .{
            .direction = direction,
            .account = account,
            .amount = amount,
            .commodity = commodity,
            .span = .{
                .source_id = direction_token.span.source_id,
                .start = direction_token.span.start,
                .end = commodity.span.end,
            },
        };
    }

    fn parseTransaction(self: *Self, allocator: std.mem.Allocator) !ast.TransactionStmt {
        const keyword = try self.expectWord("transaction");
        const date = try self.expectKind(.word);
        const narration: ?lexer.Token =
            if (self.current.?.kind == .string)
                try self.advance()
            else
                null;

        _ = try self.expectKind(.left_brace);

        var id: ?lexer.Token = null;
        if (self.matchesWord("id")) {
            _ = try self.advance();
            id = try self.expectKind(.word);
        }

        var postings: std.ArrayList(ast.PostingStmt) = .empty;
        errdefer postings.deinit(allocator);

        while (self.matchesWord("debit") or self.matchesWord("credit")) {
            const posting = try self.parsePosting();
            try postings.append(allocator, posting);
        }

        const closing_brace = try self.expectKind(.right_brace);
        return .{
            .id = id,
            .date = date,
            .narration = narration,
            .postings = postings,
            .span = .{
                .source_id = keyword.span.source_id,
                .start = keyword.span.start,
                .end = closing_brace.span.end,
            },
        };
    }

    fn currentLexerError(self: *const Self) lexer.LexerError {
        const failure = self.lexer.failure orelse unreachable;

        return switch (failure.kind) {
            .unterminated_string => error.UnterminatedString,
            .newline_in_string => error.NewlineInString,
        };
    }
};

test "parse required metadata" {
    var parser = Parser.init(
        \\meta version 1
        \\meta journal "personal"
    );

    var document = try parser.parse(std.testing.allocator);
    defer document.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("1", document.version.lexeme);
    try std.testing.expectEqualStrings("personal", document.journal_name.lexeme);

    try std.testing.expectEqual(@as(usize, 0), document.accounts.items.len);
    try std.testing.expectEqual(@as(usize, 0), document.transactions.items.len);
}

test "require version metadata first" {
    var parser = Parser.init(
        \\meta journal "personal"
        \\meta version 1
    );

    try std.testing.expectError(error.UnexpectedToken, parser.parse(std.testing.allocator));

    const failure = parser.failure.?;
    try std.testing.expectEqualStrings("journal", failure.token.lexeme);

    switch (failure.expected) {
        .word => |expected| {
            try std.testing.expectEqualStrings("version", expected);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse account declarations" {
    var parser = Parser.init(
        \\meta version 1
        \\meta journal "personal"
        \\
        \\account asset:bank
        \\account equity:opening-balances
        \\account income:salary
        \\account expense:groceries
    );

    var document = try parser.parse(std.testing.allocator);
    defer document.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), document.accounts.items.len);

    const bank = document.accounts.items[0];
    try std.testing.expectEqualStrings("asset:bank", bank.name.lexeme);
}

test "parse transaction and postings" {
    var parser = Parser.init(
        \\meta version 1
        \\meta journal "personal"
        \\
        \\account asset:bank
        \\account expense:groceries
        \\
        \\transaction 2026-01-17 "Groceries" {
        \\  id groceries-001
        \\  debit expense:groceries 82.40 AUD
        \\  credit asset:bank 82.40 AUD
        \\}
    );

    var document = try parser.parse(std.testing.allocator);
    defer document.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), document.transactions.items.len);

    const transaction = document.transactions.items[0];

    try std.testing.expectEqualStrings("2026-01-17", transaction.date.lexeme);
    try std.testing.expectEqualStrings("Groceries", transaction.narration.?.lexeme);
    try std.testing.expectEqualStrings("groceries-001", transaction.id.?.lexeme);
    try std.testing.expectEqual(@as(usize, 2), transaction.postings.items.len);
    try std.testing.expectEqual(ast.Direction.debit, transaction.postings.items[0].direction);
    try std.testing.expectEqualStrings("82.40", transaction.postings.items[0].amount.lexeme);
}

test "preserve lexer failure on first token" {
    var parser = Parser.init("\"unterminated");

    try std.testing.expectError(error.UnterminatedString, parser.parse(std.testing.allocator));
    try std.testing.expectEqual(lexer.FailureKind.unterminated_string, parser.lexer.failure.?.kind);
}

test "parser preserves source identity" {
    var parser = Parser.initWithSource(7,
        \\meta version 1
        \\meta journal "personal"
    );

    var document = try parser.parse(std.testing.allocator);
    defer document.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(source.SourceId, 7), document.version.span.source_id);
    try std.testing.expectEqual(@as(source.SourceId, 7), document.journal_name.span.source_id);
}

test "parse typed source directives" {
    var parser = Parser.init(
        \\meta version 1
        \\meta journal "personal"
        \\
        \\source accounts "accounts.fiscus"
        \\source transactions "transactions"
    );

    var document = try parser.parse(std.testing.allocator);
    defer document.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), document.sources.items.len);
    try std.testing.expectEqual(ast.SourceRole.accounts, document.sources.items[0].role);
    try std.testing.expectEqualStrings("accounts.fiscus", document.sources.items[0].path.lexeme);
    try std.testing.expectEqual(ast.SourceRole.transactions, document.sources.items[1].role);
}
