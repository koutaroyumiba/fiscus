const std = @import("std");

const source = @import("source.zig");

pub const TokenKind = enum {
    word,
    string,
    left_brace,
    right_brace,
    eof,
};

pub const Token = struct {
    kind: TokenKind,
    lexeme: []const u8,
    span: source.Span,
};

pub const LexerError = error{
    UnterminatedString,
    NewlineInString,
};

pub const FailureKind = enum {
    unterminated_string,
    newline_in_string,
};

pub const Failure = struct {
    kind: FailureKind,
    span: source.Span,
};

pub const Lexer = struct {
    source_id: source.SourceId,
    input: []const u8,
    offset: usize,
    line: usize,
    column: usize,
    failure: ?Failure,

    const Self = @This();

    pub fn init(input: []const u8) Self {
        return initWithSource(source.root_source_id, input);
    }

    pub fn initWithSource(source_id: source.SourceId, input: []const u8) Self {
        return .{
            .source_id = source_id,
            .input = input,
            .offset = 0,
            .line = 1,
            .column = 1,
            .failure = null,
        };
    }

    pub fn next(self: *Self) LexerError!Token {
        self.skip();

        const start = self.location();
        const byte = self.peek() orelse {
            return .{
                .kind = .eof,
                .lexeme = self.input[self.offset..self.offset],
                .span = .{
                    .source_id = self.source_id,
                    .start = start,
                    .end = start,
                },
            };
        };

        return switch (byte) {
            '{' => self.lexSingleByte(.left_brace),
            '}' => self.lexSingleByte(.right_brace),
            '"' => self.lexString(),
            else => self.lexWord(),
        };
    }

    // === PRIVATE ===

    fn location(self: *const Self) source.Location {
        return .{
            .offset = self.offset,
            .line = self.line,
            .column = self.column,
        };
    }

    fn peek(self: *const Self) ?u8 {
        if (self.offset >= self.input.len) {
            return null;
        }

        return self.input[self.offset];
    }

    fn advance(self: *Self) ?u8 {
        const byte = self.peek() orelse return null;

        self.offset += 1;
        if (byte == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }

        return byte;
    }

    fn skip(self: *Self) void {
        while (self.peek()) |byte| {
            switch (byte) {
                // skip whitespace
                ' ', '\t', '\r', '\n' => {
                    _ = self.advance();
                },
                // skip comment until EOL
                '#' => {
                    while (self.peek()) |comment_byte| {
                        if (comment_byte == '\n') {
                            break;
                        }

                        _ = self.advance();
                    }
                },
                else => return,
            }
        }
    }

    fn lexSingleByte(self: *Self, kind: TokenKind) Token {
        const start = self.location();
        const start_offset = self.offset;

        _ = self.advance();

        return .{
            .kind = kind,
            .lexeme = self.input[start_offset..self.offset],
            .span = .{
                .source_id = self.source_id,
                .start = start,
                .end = self.location(),
            },
        };
    }

    fn lexWord(self: *Self) Token {
        const start = self.location();
        const start_offset = self.offset;

        while (self.peek()) |byte| {
            if (isDelimiter(byte)) {
                break;
            }

            _ = self.advance();
        }

        return .{
            .kind = .word,
            .lexeme = self.input[start_offset..self.offset],
            .span = .{
                .source_id = self.source_id,
                .start = start,
                .end = self.location(),
            },
        };
    }

    fn lexString(self: *Self) LexerError!Token {
        const start = self.location();

        // consume opening quote
        _ = self.advance();
        const content_start = self.offset;

        while (self.peek()) |byte| {
            if (byte == '"') {
                const content_end = self.offset;

                // consume closing quote
                _ = self.advance();

                return .{
                    .kind = .string,
                    .lexeme = self.input[content_start..content_end],
                    .span = .{
                        .source_id = self.source_id,
                        .start = start,
                        .end = self.location(),
                    },
                };
            }

            if (byte == '\n' or byte == '\r') {
                return self.fail(.newline_in_string, start);
            }

            _ = self.advance();
        }

        return self.fail(.unterminated_string, start);
    }

    fn fail(self: *Self, kind: FailureKind, start: source.Location) LexerError {
        self.failure = .{ .kind = kind, .span = .{
            .source_id = self.source_id,
            .start = start,
            .end = self.location(),
        } };
        return switch (kind) {
            .unterminated_string => error.UnterminatedString,
            .newline_in_string => error.NewlineInString,
        };
    }
};

fn isDelimiter(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\r', '\n', '{', '}', '"', '#' => true,
        else => false,
    };
}

// TEST HELPERS

fn expectToken(lexer: *Lexer, expected_kind: TokenKind, expected_lexeme: []const u8) !Token {
    const token = try lexer.next();

    try std.testing.expectEqual(expected_kind, token.kind);
    try std.testing.expectEqualStrings(expected_lexeme, token.lexeme);

    return token;
}

test "lex journal metadata" {
    var lexer = Lexer.init(
        \\meta version 1
        \\meta journal "personal"
    );

    _ = try expectToken(&lexer, .word, "meta");
    _ = try expectToken(&lexer, .word, "version");
    _ = try expectToken(&lexer, .word, "1");

    _ = try expectToken(&lexer, .word, "meta");
    _ = try expectToken(&lexer, .word, "journal");

    const journal_name = try expectToken(&lexer, .string, "personal");

    try std.testing.expectEqual(@as(usize, 2), journal_name.span.start.line);
    try std.testing.expectEqual(@as(usize, 14), journal_name.span.start.column);

    _ = try expectToken(&lexer, .eof, "");
}

test "skip comments and track locations" {
    var lexer = Lexer.init(
        \\# Heading
        \\
        \\  account asset:bank # trailing comment
        \\{}
    );

    const account = try expectToken(&lexer, .word, "account");
    try std.testing.expectEqual(@as(usize, 3), account.span.start.line);
    try std.testing.expectEqual(@as(usize, 3), account.span.start.column);

    _ = try expectToken(&lexer, .word, "asset:bank");

    const left = try expectToken(&lexer, .left_brace, "{");
    try std.testing.expectEqual(@as(usize, 4), left.span.start.line);

    _ = try expectToken(&lexer, .right_brace, "}");
    _ = try expectToken(&lexer, .eof, "");
}

test "reject unterminated string" {
    var lexer = Lexer.init("\"personal");

    try std.testing.expectError(error.UnterminatedString, lexer.next());
}

test "reject newline inside string" {
    var lexer = Lexer.init("\"personal\njournal\"");

    try std.testing.expectError(error.NewlineInString, lexer.next());
}

test "tokens retain source identity" {
    var lexer = Lexer.initWithSource(42, "account");
    const token = try lexer.next();

    try std.testing.expectEqual(@as(source.SourceId, 42), token.span.source_id);
}
