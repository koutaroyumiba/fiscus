const std = @import("std");

pub const Month = std.time.epoch.Month;

pub const DateError = error{ InvalidYear, InvalidDay };

pub const Date = struct {
    year: u16,
    month: Month,
    day: u8,

    pub fn init(year: u16, month: Month, day: u8) DateError!Date {
        if (year <= 0 or year >= 9999) {
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

test "Date.init validates dates" {
    try std.testing.expectEqual(Date{ .year = 2024, .month = .feb, .day = 29 }, try Date.init(2024, .feb, 29));
    try std.testing.expectError(error.InvalidYear, Date.init(12024, .jan, 2));
    try std.testing.expectError(error.InvalidDay, Date.init(2023, .feb, 29));
    try std.testing.expectError(error.InvalidDay, Date.init(2024, .jan, 0));
}
