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
        const commodity = self.journal.catalog.get(self.balance.amount.commodity).?;

        var value_output = std.Io.Writer.Allocating.init(ctx.arena);
        defer value_output.deinit();

        self.journal.catalog.writeAmountValue(&value_output.writer, self.balance.amount) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
            error.UnknownCommodity => unreachable,
        };

        var row_output = std.Io.Writer.Allocating.init(ctx.arena);
        defer row_output.deinit();

        row_output.writer.print(
            "{s:<45} {s:>18}  {s}",
            .{ account.name, value_output.written(), commodity.symbol },
        ) catch return error.OutOfMemory;

        const text: vxfw.Text = .{
            .text = row_output.written(),
            .softwrap = false,
            .width_basis = .parent,
        };
        var surface = try text.draw(ctx);
        surface.widget = self.widget();

        return surface;
    }
};
