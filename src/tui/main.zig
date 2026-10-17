const std = @import("std");

const fiscus = @import("fiscus");
const vaxis = @import("vaxis");

const BalanceRow = @import("balance.widget.zig").BalanceRow;

const vxfw = vaxis.vxfw;

const RowSet = struct {
    rows: []BalanceRow,
    widgets: []vxfw.Widget,

    fn deinit(self: RowSet, allocator: std.mem.Allocator) void {
        allocator.free(self.widgets);
        allocator.free(self.rows);
    }
};

const Model = struct {
    allocator: std.mem.Allocator,
    application: *const fiscus.application.Application,
    journal: *const fiscus.accounting.Journal,
    balance_result: fiscus.application.BalanceResult,

    rows: []BalanceRow,
    row_widgets: []vxfw.Widget,
    list: vxfw.ListView,

    prefix_field: vxfw.TextField,
    editing_prefix: bool = false,
    current_prefix: ?[]u8 = null,
    status: ?[]const u8 = null,

    fn init(
        allocator: std.mem.Allocator,
        application: *const fiscus.application.Application,
        journal: *const fiscus.accounting.Journal,
    ) !Model {
        var balance_result = try application.balances(.all);
        errdefer balance_result.deinit();

        const row_set = try buildRows(allocator, journal, &balance_result);
        errdefer row_set.deinit(allocator);

        return .{
            .allocator = allocator,
            .application = application,
            .journal = journal,
            .balance_result = balance_result,
            .rows = row_set.rows,
            .row_widgets = row_set.widgets,
            .list = .{
                .children = .{ .slice = row_set.widgets },
                .item_count = @intCast(row_set.widgets.len),
            },
            .prefix_field = vxfw.TextField.init(allocator),
        };
    }

    fn bindCallbacks(self: *Model) void {
        self.prefix_field.userdata = self;
        self.prefix_field.onSubmit = onPrefixSubmit;
    }

    fn deinit(self: *Model) void {
        self.prefix_field.deinit();
        if (self.current_prefix) |prefix| {
            self.allocator.free(prefix);
        }
        self.allocator.free(self.row_widgets);
        self.allocator.free(self.rows);
        self.balance_result.deinit();
        self.* = undefined;
    }

    pub fn widget(self: *Model) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Model.typeErasedEventHandler,
            .drawFn = Model.typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        const self: *Model = @ptrCast(@alignCast(ptr));

        switch (event) {
            .init => return ctx.requestFocus(self.list.widget()),
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }

                if (self.editing_prefix) {
                    if (key.matches(vaxis.Key.escape, .{})) {
                        self.editing_prefix = false;
                        self.status = null;
                        try ctx.requestFocus(self.list.widget());
                        return ctx.consumeAndRedraw();
                    }
                    return;
                }

                if (key.matches('q', .{})) {
                    ctx.quit = true;
                    return;
                }

                if (key.matches('/', .{})) {
                    self.editing_prefix = true;
                    self.status = null;
                    try ctx.requestFocus(self.prefix_field.widget());
                    return ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn onPrefixSubmit(
        maybe_ptr: ?*anyopaque,
        ctx: *vxfw.EventContext,
        prefix: []const u8,
    ) anyerror!void {
        const ptr = maybe_ptr orelse return;
        const self: *Model = @ptrCast(@alignCast(ptr));

        if (!try self.applyPrefix(prefix)) {
            return ctx.consumeAndRedraw();
        }

        self.editing_prefix = false;
        try ctx.requestFocus(self.list.widget());
        ctx.consumeAndRedraw();
    }

    fn applyPrefix(self: *Model, prefix: []const u8) std.mem.Allocator.Error!bool {
        const query: fiscus.application.BalanceQuery = if (prefix.len == 0)
            .all
        else
            .{ .prefix = .{ .value = prefix, .sort = .account } };

        var new_result = self.application.balances(query) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.JournalUnavailable => unreachable,
            error.InvalidAccountPrefix => {
                self.status = "Invalid account prefix";
                return false;
            },
            error.Overflow => {
                self.status = "Account balance overflow";
                return false;
            },
        };
        errdefer new_result.deinit();

        const new_rows = try buildRows(self.allocator, self.journal, &new_result);
        errdefer new_rows.deinit(self.allocator);

        const new_prefix: ?[]u8 = if (prefix.len == 0)
            null
        else
            try self.allocator.dupe(u8, prefix);
        errdefer if (new_prefix) |value| self.allocator.free(value);

        self.allocator.free(self.row_widgets);
        self.allocator.free(self.rows);
        self.balance_result.deinit();

        self.balance_result = new_result;
        self.rows = new_rows.rows;
        self.row_widgets = new_rows.widgets;
        self.list.children = .{ .slice = self.row_widgets };
        self.list.item_count = @intCast(self.row_widgets.len);
        self.list.jumpToItem(0);

        if (self.current_prefix) |value| {
            self.allocator.free(value);
        }
        self.current_prefix = new_prefix;
        self.status = null;

        return true;
    }

    fn formatFilteredTotals(
        self: *const Model,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error![]const u8 {
        const report = switch (self.balance_result) {
            .all => unreachable,
            .prefix => |prefix_report| prefix_report,
        };

        var output = std.Io.Writer.Allocating.init(allocator);
        defer output.deinit();

        output.writer.writeAll("Filtered total: ") catch return error.OutOfMemory;
        if (report.amounts.items.len == 0) {
            output.writer.writeAll("no balances") catch return error.OutOfMemory;
        }

        for (report.amounts.items, 0..) |amount, index| {
            if (index != 0) {
                output.writer.writeAll(" | ") catch return error.OutOfMemory;
            }

            self.journal.catalog.writeAmount(&output.writer, amount) catch |err| switch (err) {
                error.WriteFailed => return error.OutOfMemory,
                error.UnknownCommodity => unreachable,
            };
        }

        return output.toOwnedSlice();
    }

    fn typeErasedDrawFn(
        ptr: *anyopaque,
        ctx: vxfw.DrawContext,
    ) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Model = @ptrCast(@alignCast(ptr));
        const max_size = ctx.max.size();

        const title_text = try ctx.arena.print("Fiscus - {s}", .{self.journal.name});
        const title: vxfw.Text = .{ .text = title_text };
        const prefix_label: vxfw.Text = .{ .text = "Prefix: " };
        const current_prefix_text = if (self.current_prefix) |prefix|
            try ctx.arena.print("Current filter: {s}", .{prefix})
        else
            "Current filter: all accounts";
        const current_prefix: vxfw.Text = .{ .text = current_prefix_text };

        const prefix_width = max_size.width -| 8;
        const prefix_context = ctx.withConstraints(
            .{ .width = prefix_width, .height = 1 },
            .{ .width = prefix_width, .height = 1 },
        );

        const has_filter = self.current_prefix != null;
        const list_row: u16 = if (has_filter) 6 else 5;
        const list_height = max_size.height -| list_row;
        const list_context = ctx.withConstraints(.{}, .{
            .width = max_size.width,
            .height = list_height,
        });

        const child_count: usize = 5 + @as(usize, @intFromBool(has_filter)) + @as(usize, @intFromBool(self.status != null));
        const children = try ctx.arena.alloc(vxfw.SubSurface, child_count);
        children[0] = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try title.draw(ctx),
        };
        children[1] = .{
            .origin = .{ .row = 2, .col = 0 },
            .surface = try prefix_label.draw(ctx),
        };
        children[2] = .{
            .origin = .{ .row = 2, .col = 8 },
            .surface = try self.prefix_field.draw(prefix_context),
        };
        children[3] = .{
            .origin = .{ .row = 3, .col = 0 },
            .surface = try current_prefix.draw(ctx),
        };
        var child_index: usize = 4;
        if (has_filter) {
            const totals_text: vxfw.Text = .{
                .text = try self.formatFilteredTotals(ctx.arena),
                .softwrap = false,
                .overflow = .ellipsis,
                .width_basis = .parent,
            };
            children[child_index] = .{
                .origin = .{ .row = 4, .col = 0 },
                .surface = try totals_text.draw(ctx),
            };
            child_index += 1;
        }

        if (self.status) |status| {
            const status_text: vxfw.Text = .{ .text = status };
            children[child_index] = .{
                .origin = .{ .row = list_row - 1, .col = 0 },
                .surface = try status_text.draw(ctx),
            };
            child_index += 1;
        }

        children[child_index] = .{
            .origin = .{ .row = list_row, .col = 0 },
            .surface = try self.list.draw(list_context),
        };

        return .{
            .size = max_size,
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }
};

fn buildRows(
    allocator: std.mem.Allocator,
    journal: *const fiscus.accounting.Journal,
    result: *const fiscus.application.BalanceResult,
) std.mem.Allocator.Error!RowSet {
    const balances = switch (result.*) {
        .all => |report| report.balances.items,
        .prefix => |report| report.balances.items,
    };

    const rows = try allocator.alloc(BalanceRow, balances.len);
    errdefer allocator.free(rows);

    const widgets = try allocator.alloc(vxfw.Widget, rows.len);
    errdefer allocator.free(widgets);

    for (rows, balances, widgets) |*row, balance, *row_widget| {
        row.* = .{ .journal = journal, .balance = balance };
        row_widget.* = row.widget();
    }

    return .{ .rows = rows, .widgets = widgets };
}

pub fn run(init: std.process.Init, path: []const u8) !void {
    const io = init.io;
    const allocator = init.gpa;

    var application = try fiscus.application.Application.load(
        allocator,
        io,
        std.Io.Dir.cwd(),
        path,
    );
    defer application.deinit();

    const journal = application.journal() orelse return error.InvalidJournal;

    var buffer: [1024]u8 = undefined;
    var app: vxfw.App = try .init(io, allocator, init.environ_map, &buffer);
    defer app.deinit();

    var model = try Model.init(allocator, &application, journal);
    defer model.deinit();
    model.bindCallbacks();

    try app.run(model.widget(), .{});
}
