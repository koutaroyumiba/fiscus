const std = @import("std");

pub const Month = std.time.epoch.Month;

pub const DateError = error{ InvalidFormat, InvalidYear, InvalidMonth, InvalidDay };

pub const Date = struct {
    year: u16,
    month: Month,
    day: u8,

    pub fn init(year: u16, month: Month, day: u8) DateError!Date {
        if (year == 0 or year > 9999) {
            return error.InvalidYear;
        }

        const max_days = std.time.epoch.getDaysInMonth(year, month);
        if (day <= 0 or day > max_days) {
            return error.InvalidDay;
        }

        return Date{
            .year = year,
            .month = month,
            .day = day,
        };
    }

    pub fn parse(text: []const u8) DateError!Date {
        if (text.len != 10 or text[4] != '-' or text[7] != '-') {
            return error.InvalidFormat;
        }

        const year = try parseDigits(text[0..4]);
        const month_u16 = try parseDigits(text[5..7]);
        const day_u16 = try parseDigits(text[8..10]);

        if (month_u16 < 1 or month_u16 > 12) {
            return error.InvalidMonth;
        }
        const month_u4 = std.math.cast(u4, month_u16) orelse return error.InvalidMonth;
        const day = std.math.cast(u8, day_u16) orelse return error.InvalidDay;

        const month: Month = @fromBackingInt(month_u4);

        return Date.init(year, month, day);
    }

    // === GETTERS AND FORMATTERS

    pub fn iso(self: Date) [10]u8 {
        // iso format: "1234-67-90" (10 bytes)
        const buffer: [10]u8 = undefined;
        _ = std.mem.print(&buffer, "{d:0>4}-{d:0>2}-{d:0>2}", .{ self.year, @backingInt(self.month), self.day }) catch unreachable;

        return buffer;
    }

    // TODO: to_epoch_day()?

    pub fn format(self: Date, w: *std.Io.Writer) !void {
        return try w.print("{}", .{self.iso()});
    }
};

pub fn now(io: std.Io) i64 {
    const timestamp: std.Io.Timestamp = std.Io.Clock.real.now(io);
    const unix_seconds: i64 = @divFloor(timestamp.nanoseconds, std.time.ns_per_s);

    return unix_seconds;
}

fn parseDigits(text: []const u8) DateError!u16 {
    var value: u16 = 0;

    for (text) |char| {
        if (char < '0' or char > '9') {
            return error.InvalidFormat;
        }

        value = value * 10 + (char - '0');
    }

    return value;
}

test "Date.init validates dates" {
    try std.testing.expectEqual(Date{ .year = 2024, .month = .feb, .day = 29 }, try Date.init(2024, .feb, 29));
    try std.testing.expectError(error.InvalidYear, Date.init(12024, .jan, 2));
    try std.testing.expectError(error.InvalidDay, Date.init(2023, .feb, 29));
    try std.testing.expectError(error.InvalidDay, Date.init(2024, .jan, 0));
}

test "parse ISO date" {
    try std.testing.expectEqual(Date{ .year = 2026, .month = .jan, .day = 17 }, try Date.parse("2026-01-17"));
}

test "reject invalid ISO dates" {
    try std.testing.expectError(error.InvalidFormat, Date.parse("2026/01/17"));
    try std.testing.expectError(error.InvalidMonth, Date.parse("2026-13-01"));
    try std.testing.expectError(error.InvalidDay, Date.parse("2026-02-30"));
}
