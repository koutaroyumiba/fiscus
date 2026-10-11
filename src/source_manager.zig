const std = @import("std");

const source = @import("lang/source.zig");

pub const SourceFile = struct {
    path: []const u8,
    text: []const u8,
};

pub const SourceManagerError = error{
    DuplicatePath,
    TooManySources,
};

pub const SourceManager = struct {
    allocator: std.mem.Allocator,
    files: std.ArrayList(SourceFile),
    ids_by_path: std.StringHashMap(source.SourceId),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .files = .empty,
            .ids_by_path = std.StringHashMap(source.SourceId).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.ids_by_path.deinit();

        for (self.files.items) |file| {
            self.allocator.free(file.path);
            self.allocator.free(file.text);
        }

        self.files.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn add(self: *Self, path: []const u8, text: []const u8) !source.SourceId {
        if (self.ids_by_path.contains(path)) {
            return error.DuplicatePath;
        }

        if (self.files.items.len > std.math.maxInt(source.SourceId)) {
            return error.TooManySources;
        }

        try self.files.ensureUnusedCapacity(self.allocator, 1);
        try self.ids_by_path.ensureUnusedCapacity(1);

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);
        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        const id: source.SourceId = @intCast(self.files.items.len);
        self.files.appendAssumeCapacity(.{
            .path = owned_path,
            .text = owned_text,
        });
        self.ids_by_path.putAssumeCapacityNoClobber(owned_path, id);

        return id;
    }

    pub fn get(self: *const Self, id: source.SourceId) ?SourceFile {
        const index = std.math.cast(usize, id) orelse return null;
        if (index >= self.files.items.len) {
            return null;
        }

        return self.files.items[index];
    }

    pub fn find(self: *const Self, path: []const u8) ?source.SourceId {
        return self.ids_by_path.get(path);
    }
};

test "register and retrieve sources" {
    var manager = SourceManager.init(std.testing.allocator);
    defer manager.deinit();

    const root = try manager.add("journal.fiscus", "meta version 1");
    const accounts = try manager.add("accounts.fiscus", "account asset:bank");

    try std.testing.expectEqual(source.root_source_id, root);
    try std.testing.expectEqual(@as(source.SourceId, 1), accounts);
    try std.testing.expectEqualStrings("account asset:bank", manager.get(accounts).?.text);
    try std.testing.expectEqual(accounts, manager.find("accounts.fiscus").?);
}

test "reject duplicate source paths" {
    var manager = SourceManager.init(std.testing.allocator);
    defer manager.deinit();

    _ = try manager.add("accounts.fiscus", "");

    try std.testing.expectError(error.DuplicatePath, manager.add("accounts.fiscus", ""));
}
