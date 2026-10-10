const std = @import("std");

const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

// crazy use of a tagged union :D
pub const Expected = union(enum) {
    kind: lexer.TokenKind,
    word: []const u8,
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
    current: lexer.Token,
    failure: ?Failure,

    const Self = @This();

    pub fn init(input: []const u8) lexer.LexerError!Self {
        var tokenizer = lexer.Lexer.init(input);
        const current = try tokenizer.next();

        return .{
            .lexer = tokenizer,
            .current = current,
            .failure = null,
        };
    }

    pub fn parse(self: *Self, allocator: std.mem.Allocator) !ast.Document {
        _ = try self.expectWord("meta");
        _ = try self.expectWord("version");
        const version = try self.expectKind(.word);

        _ = try self.expectWord("meta");
        _ = try self.expectWord("journal");
        const journal_name = try self.expectKind(.string);

        var document = ast.Document.init(version, journal_name);
        errdefer document.deinit(allocator);

        while (self.matchesWord("account")) {
            const account = try self.parseAccount();
            try document.accounts.append(allocator, account);
        }

        // tmp until acc and tx parsing are added
        _ = try self.expectKind(.eof);
        return document;
    }

    fn advance(self: *Self) !lexer.Token {
        const consumed = self.current;
        self.current = try self.lexer.next();
        return consumed;
    }

    fn expectKind(self: *Self, expected: lexer.TokenKind) !lexer.Token {
        if (self.current.kind != expected) {
            self.failure = .{
                .token = self.current,
                .expected = .{ .kind = expected },
            };

            return error.UnexpectedToken;
        }

        return self.advance();
    }

    fn expectWord(self: *Self, expected: []const u8) !lexer.Token {
        if (self.current.kind != .word or !std.mem.eql(u8, self.current.lexeme, expected)) {
            self.failure = .{
                .token = self.current,
                .expected = .{ .word = expected },
            };

            return error.UnexpectedToken;
        }

        return self.advance();
    }

    fn matchesWord(self: *const Self, expected: []const u8) bool {
        return self.current.kind == .word and std.mem.eql(u8, self.current.lexeme, expected);
    }

    fn parseAccount(self: *Self) !ast.AccountStmt {
        const keyword = try self.expectWord("account");
        const name = try self.expectKind(.word);

        return .{
            .name = name,
            .span = .{
                .start = keyword.span.start,
                .end = name.span.end,
            },
        };
    }
};

test "parse required metadata" {
    var parser = try Parser.init(
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
    var parser = try Parser.init(
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
    var parser = try Parser.init(
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
