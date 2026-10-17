const std = @import("std");

const fiscus = @import("fiscus");
const vaxis = @import("vaxis");

const vxfw = vaxis.vxfw;

const Model = struct {
    journal: *const fiscus.accounting.Journal,
    report: *const fiscus.reports.BalanceReport,

    pub fn widget(self: *Model) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Model.typeErasedEventHandler,
            .drawFn = Model.typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(_: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }
            },
            else => {},
        }
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Model = @ptrCast(@alignCast(ptr));
        const max_size = ctx.max.size();
        const available_rows: usize = if (max_size.height > 2) @intCast(max_size.height - 2) else 0;

        const visible_count = @min(available_rows, self.report.balances.items.len);

        const title_text = try ctx.arena.print("Fiscus - {s}", .{self.journal.name});
        const text1: vxfw.Text = .{ .text = title_text };

        const children = try ctx.arena.alloc(vxfw.SubSurface, visible_count + 1);
        children[0] = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try text1.draw(ctx),
        };

        for (self.report.balances.items[0..visible_count], 0..) |balance, index| {
            const row_text = try self.formatBalance(ctx.arena, balance);
            const text: vxfw.Text = .{ .text = row_text };

            children[index + 1] = .{
                .origin = .{ .row = @intCast(index + 2), .col = 0 },
                .surface = try text.draw(ctx),
            };
        }

        return .{
            .size = max_size,
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }

    fn formatBalance(
        self: *const Model,
        allocator: std.mem.Allocator,
        balance: fiscus.reports.Balance,
    ) std.mem.Allocator.Error![]const u8 {
        const account = self.journal.getAccount(balance.account).?;

        var output = std.Io.Writer.Allocating.init(allocator);
        defer output.deinit();

        output.writer.print("{s:<45} ", .{account.name}) catch return error.OutOfMemory;

        self.journal.catalog.writeAmount(&output.writer, balance.amount) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
            error.UnknownCommodity => unreachable,
        };

        return output.toOwnedSlice();
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const path = if (args.len >= 2) args[1] else "journal.fiscus";

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

    var model: Model = .{ .journal = journal, .report = report };

    try app.run(model.widget(), .{});
}
