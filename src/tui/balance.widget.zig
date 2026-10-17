const std = @import("std");

const fiscus = @import("fiscus");
const vaxis = @import("vaxis");

const vxfw = vaxis.vxfw;

pub const BalanceRow = struct {
    journal: *const fiscus.accounting.Journal,
    balance: fiscus.reports.Balance,

    pub fn widget(self: *BalanceRow) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = typeErasedDrawFn,
        };
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *BalanceRow = @ptrCast(@alignCast(ptr));

        const account = self.journal.getAccount(self.balance.account).?;

        var output = std.Io.Writer.Allocating.init(ctx.arena);
        defer output.deinit();

        output.writer.print("{s:<45} ", .{account.name}) catch return error.OutOfMemory;

        self.journal.catalog.writeAmount(&output.writer, self.balance.amount) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
            error.UnknownCommodity => unreachable,
        };

        const text: vxfw.Text = .{
            .text = output.written(),
            .softwrap = false,
            .width_basis = .parent,
        };
        var surface = try text.draw(ctx);
        surface.widget = self.widget();

        return surface;
    }
};
