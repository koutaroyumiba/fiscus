const std = @import("std");
const Io = std.Io;

const fiscus = @import("fiscus");
const money = fiscus.money;

pub fn main() !void {
    const m = money.Money{
        .amount = 64,
        .currency = money.CurrencyCode.AUD,
    };
    std.debug.print("{f}", .{m});
}
