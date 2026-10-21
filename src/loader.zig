const std = @import("std");

const accounting = @import("ledger/root.zig");
const decoder = @import("decoder.zig");
const lexer = @import("lang/lexer.zig");
const parser = @import("lang/parser.zig");

pub const Failure = union(enum) {
    lexer: lexer.Failure,
    parser: parser.Failure,
    decoder: decoder.Failure,
};

pub const Result = union(enum) {
    journal: accounting.Journal,
    failure: Failure,

    pub fn deinit(self: *Result) void {
        switch (self.*) {
            .journal => |*journal| journal.deinit(),
            .failure => {},
        }

        self.* = undefined;
    }
};

pub fn load(allocator: std.mem.Allocator, input: []const u8) !Result {
    var parser_instance = parser.Parser.init(input);

    var document = parser_instance.parse(allocator) catch |err| {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,

            error.UnterminatedString,
            error.NewlineInString,
            => .{ .failure = .{ .lexer = parser_instance.lexer.failure.? } },

            error.UnexpectedToken => .{ .failure = .{ .parser = parser_instance.failure.? } },
        };
    };
    defer document.deinit(allocator);

    var decoder_instance = decoder.Decoder.init(allocator);

    const journal = decoder_instance.decode(&document) catch |err| {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidDocument => .{
                .failure = .{ .decoder = decoder_instance.failure.? },
            },
        };
    };

    return .{ .journal = journal };
}
