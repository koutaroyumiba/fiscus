const std = @import("std");

const fiscus = @import("fiscus");
const vaxis = @import("vaxis");

const BalanceRow = @import("balance.widget.zig").BalanceRow;

const vxfw = vaxis.vxfw;

const Model = struct {
    journal: *const fiscus.accounting.Journal,
    report: *const fiscus.reports.BalanceReport,

    rows: []BalanceRow,
    row_widgets: []vxfw.Widget,
    list: vxfw.ListView,

    fn init(
        allocator: std.mem.Allocator,
        journal: *const fiscus.accounting.Journal,
        report: *const fiscus.reports.BalanceReport,
    ) !Model {
        const rows = try allocator.alloc(BalanceRow, report.balances.items.len);
        errdefer allocator.free(rows);

        const row_widgets = try allocator.alloc(vxfw.Widget, rows.len);
        errdefer allocator.free(row_widgets);

        for (rows, report.balances.items, row_widgets) |*row, balance, *row_widget| {
            row.* = .{ .journal = journal, .balance = balance };
            row_widget.* = row.widget();
        }

        return .{
            .journal = journal,
            .report = report,
            .rows = rows,
            .row_widgets = row_widgets,
            .list = .{
                .children = .{ .slice = row_widgets },
                .item_count = @intCast(row_widgets.len),
            },
        };
    }

    fn deinit(self: *Model, allocator: std.mem.Allocator) void {
        allocator.free(self.row_widgets);
        allocator.free(self.rows);
        self.* = undefined;
    }

    pub fn widget(self: *Model) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Model.typeErasedEventHandler,
            .drawFn = Model.typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *Model = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }
            },
            else => {},
        }

        return self.list.handleEvent(ctx, event);
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Model = @ptrCast(@alignCast(ptr));
        const max_size = ctx.max.size();

        const title_text = try ctx.arena.print("Fiscus - {s}", .{self.journal.name});
        const text1: vxfw.Text = .{ .text = title_text };

        const list_height = max_size.height -| 2;
        const list_context = ctx.withConstraints(.{}, .{
            .width = max_size.width,
            .height = list_height,
        });

        const children = try ctx.arena.alloc(vxfw.SubSurface, 2);
        children[0] = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try text1.draw(ctx),
        };
        children[1] = .{
            .origin = .{ .row = 2, .col = 0 },
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

pub fn run(init: std.process.Init, path: []const u8) !void {
    const io = init.io;
    const allocator = init.gpa;

    var application = try fiscus.application.Application.load(allocator, io, std.Io.Dir.cwd(), path);
    defer application.deinit();

    const journal = application.journal() orelse return error.InvalidJournal;

    var balance_result = try application.balances(.all);
    defer balance_result.deinit();

    const report = switch (balance_result) {
        .all => |*report| report,
        .prefix => unreachable,
    };

    var buffer: [1024]u8 = undefined;
    var app: vxfw.App = try .init(io, allocator, init.environ_map, &buffer);
    defer app.deinit();

    var model = try Model.init(allocator, journal, report);
    defer model.deinit(allocator);

    try app.run(model.widget(), .{});
}
