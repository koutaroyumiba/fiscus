const std = @import("std");

const ast = @import("lang/ast.zig");
const decoder = @import("decoder.zig");
const lexer = @import("lang/lexer.zig");
const loader = @import("loader.zig");
const parser = @import("lang/parser.zig");
const source = @import("lang/source.zig");
const source_manager = @import("source_manager.zig");

const MAX_FILE_SIZE = 16 * 1024 * 1024;

const LoadedDocument = struct {
    role: ast.SourceRole,
    document: ast.Document,
};

pub const Workspace = struct {
    sources: source_manager.SourceManager,
    result: loader.Result,

    pub fn deinit(self: *Workspace) void {
        self.result.deinit();
        self.sources.deinit();
        self.* = undefined;
    }
};

const ParseResult = union(enum) {
    document: ast.Document,
    failure: loader.Failure,
};

pub fn load(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, root_path: []const u8) !Workspace {
    var sources = source_manager.SourceManager.init(allocator);
    errdefer sources.deinit();

    const root_id = try readSource(allocator, io, dir, &sources, root_path);
    const root_file = sources.get(root_id).?;

    var root = switch (try parseDocument(allocator, root_id, root_file.text)) {
        .document => |document| document,
        .failure => |failure| {
            return failedWorkspace(sources, failure);
        },
    };
    defer root.deinit(allocator);

    var loaded: std.ArrayList(LoadedDocument) = .empty;
    defer {
        for (loaded.items) |*item| {
            item.document.deinit(allocator);
        }
        loaded.deinit(allocator);
    }

    for (root.sources.items) |source_statement| {
        const path = try resolveSourcePath(allocator, root_path, source_statement.path.lexeme);
        defer allocator.free(path);

        const stat = try dir.statFile(io, path, .{});
        switch (stat.kind) {
            .file => {
                if (try loadDocument(allocator, io, dir, &sources, &loaded, source_statement.role, path)) |failure| {
                    return failedWorkspace(sources, failure);
                }
            },
            .directory => {
                var paths = try discoverSourceFiles(allocator, io, dir, path);
                defer freePaths(allocator, &paths);

                for (paths.items) |source_path| {
                    if (try loadDocument(
                        allocator,
                        io,
                        dir,
                        &sources,
                        &loaded,
                        source_statement.role,
                        source_path,
                    )) |failure| {
                        return failedWorkspace(sources, failure);
                    }
                }
            },
            else => return error.UnsupportedSourceKind,
        }
    }

    var source_documents: std.ArrayList(decoder.SourceDocument) = .empty;
    defer source_documents.deinit(allocator);

    try source_documents.ensureTotalCapacity(allocator, loaded.items.len);
    for (loaded.items) |*item| {
        source_documents.appendAssumeCapacity(.{ .role = item.role, .document = &item.document });
    }

    var decoder_instance = decoder.Decoder.init(allocator);
    const journal = decoder_instance.decodeWorkspace(&root, source_documents.items) catch |err| {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidDocument => failedWorkspace(sources, .{ .decoder = decoder_instance.failure.? }),
        };
    };

    return .{
        .sources = sources,
        .result = .{ .journal = journal },
    };
}

fn loadDocument(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    sources: *source_manager.SourceManager,
    loaded: *std.ArrayList(LoadedDocument),
    role: ast.SourceRole,
    path: []const u8,
) !?loader.Failure {
    const source_id = try readSource(allocator, io, dir, sources, path);
    const file = sources.get(source_id).?;
    var document = switch (try parseDocument(allocator, source_id, file.text)) {
        .document => |document| document,
        .failure => |failure| return failure,
    };

    loaded.append(allocator, .{ .role = role, .document = document }) catch |err| {
        document.deinit(allocator);
        return err;
    };

    return null;
}

fn discoverSourceFiles(
    allocator: std.mem.Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    directory_path: []const u8,
) !std.ArrayList([]u8) {
    var paths: std.ArrayList([]u8) = .empty;
    errdefer freePaths(allocator, &paths);

    var directory = try parent.openDir(io, directory_path, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer directory.close(io);

    var walker = try directory.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) {
            if (isHidden(entry.basename)) {
                walker.leave(io);
            }

            continue;
        }

        if (entry.kind != .file or isHidden(entry.basename) or !std.mem.endsWith(u8, entry.basename, ".fiscus")) {
            continue;
        }

        const path = try std.fs.path.join(allocator, &.{ directory_path, entry.path });
        paths.append(allocator, path) catch |err| {
            allocator.free(path);
            return err;
        };
    }

    std.mem.sort([]u8, paths.items, {}, lessThanPath);
    return paths;
}

fn isHidden(name: []const u8) bool {
    return name.len != 0 and name[0] == '.';
}

fn lessThanPath(_: void, left: []u8, right: []u8) bool {
    return std.mem.order(u8, left, right) == .lt;
}

fn freePaths(allocator: std.mem.Allocator, paths: *std.ArrayList([]u8)) void {
    for (paths.items) |path| {
        allocator.free(path);
    }

    paths.deinit(allocator);
}

fn parseDocument(allocator: std.mem.Allocator, source_id: source.SourceId, input: []const u8) !ParseResult {
    var parser_instance = parser.Parser.initWithSource(source_id, input);
    const document = parser_instance.parse(allocator) catch |err| {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,

            error.UnterminatedString,
            error.NewlineInString,
            => .{
                .failure = .{
                    .lexer = parser_instance.lexer.failure.?,
                },
            },
            error.UnexpectedToken => .{
                .failure = .{
                    .parser = parser_instance.failure.?,
                },
            },
        };
    };

    return .{ .document = document };
}

fn readSource(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    sources: *source_manager.SourceManager,
    path: []const u8,
) !source.SourceId {
    const text = try dir.readFileAlloc(io, path, allocator, .limited(MAX_FILE_SIZE));
    defer allocator.free(text);

    return sources.add(path, text);
}

fn resolveSourcePath(allocator: std.mem.Allocator, root_path: []const u8, referenced_path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(referenced_path)) {
        return allocator.dupe(u8, referenced_path);
    }

    const root_directory = std.fs.path.dirname(root_path) orelse ".";
    return std.fs.path.join(allocator, &.{ root_directory, referenced_path });
}

fn failedWorkspace(sources: source_manager.SourceManager, failure: loader.Failure) Workspace {
    return .{
        .sources = sources,
        .result = .{ .failure = failure },
    };
}

test "workspace parser retains source identity" {
    var sources = source_manager.SourceManager.init(std.testing.allocator);
    defer sources.deinit();

    const source_id = try sources.add("accounts.fiscus",
        \\meta version 1
        \\meta journal "personal"
        \\
        \\invalid
    );

    const file = sources.get(source_id).?;

    var result = try parseDocument(std.testing.allocator, source_id, file.text);
    switch (result) {
        .failure => |failure| switch (failure) {
            .parser => |parser_failure| {
                try std.testing.expectEqual(source_id, parser_failure.token.span.source_id);
            },
            else => return error.UnexpectedFailureKind,
        },
        .document => |*document| {
            document.deinit(std.testing.allocator);
            return error.ExpectedFailure;
        },
    }
}

test "load explicit workspace source files" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "journal.fiscus",
        .data =
        \\meta version 1
        \\meta journal "personal"
        \\
        \\source accounts "accounts.fiscus"
        \\source transactions "transactions.fiscus"
        ,
    });

    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "accounts.fiscus",
        .data =
        \\meta version 1
        \\meta journal "personal"
        \\
        \\account asset:bank
        \\account equity:opening-balances
        ,
    });

    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "transactions.fiscus",
        .data =
        \\meta version 1
        \\meta journal "personal"
        \\
        \\transaction 2026-01-01 "Opening balance" {
        \\  debit asset:bank 1000.00 AUD
        \\  credit equity:opening-balances 1000.00 AUD
        \\}
        ,
    });

    var workspace = try load(std.testing.allocator, std.testing.io, temporary.dir, "journal.fiscus");
    defer workspace.deinit();

    switch (workspace.result) {
        .journal => |journal| {
            try std.testing.expectEqual(@as(usize, 2), journal.accounts.items.len);
            try std.testing.expectEqual(@as(usize, 1), journal.transactions.items.len);
        },
        .failure => return error.UnexpectedFailure,
    }
}
