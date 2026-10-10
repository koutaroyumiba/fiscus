const std = @import("std");

const MoneyError = error{
    CurrencyMismatch,
    Overflow,
};

/// Follows ISO 4217
pub const CurrencyCode = enum {
    AUD,
    NZD,

    pub fn decimal(self: CurrencyCode) u8 {
        return switch (self) {
            .AUD, .NZD => 2,
        };
    }
};

pub const Money = struct {
    amount: i64,
    currency: CurrencyCode,

    // TODO: convert(Money, Currency, Rate, Opts);

    // === ARITHMETIC OPERATIONS ===

    pub fn negate(self: Money) MoneyError!Money {
        return Money{
            .amount = try std.math.negate(self.amount),
            .currency = self.currency,
        };
    }

    pub fn add(self: Money, other: Money) MoneyError!Money {
        if (self.currency != other.currency) {
            return MoneyError.CurrencyMismatch;
        }

        return Money{
            .amount = try std.math.add(i64, self.amount, other.amount),
            .currency = self.currency,
        };
    }

    pub fn sub(self: Money, other: Money) MoneyError!Money {
        if (self.currency != other.currency) {
            return MoneyError.CurrencyMismatch;
        }

        return Money{
            .amount = try std.math.sub(i64, self.amount, other.amount),
            .currency = self.currency,
        };
    }

    // === COMPARISON OPERATIONS ===

    pub fn eql(self: Money, other: Money) bool {
        return (self.currency == other.currency) and (self.amount == other.amount);
    }

    /// Ordering function
    ///
    /// Usage:
    /// const less_than = (try a.order(b)).compare(.lt)
    pub fn order(self: Money, other: Money) MoneyError!std.math.Order {
        if (self.currency != other.currency) {
            return error.CurrencyMismatch;
        }

        return std.math.order(self.amount, other.amount);
    }

    // === GETTERS AND FORMATTERS ===

    pub fn get_amount(self: Money) i64 {
        return self.amount;
    }

    pub fn get_currency(self: Money) CurrencyCode {
        return self.currency;
    }

    pub fn format(self: Money, w: *std.Io.Writer) !void {
        return try w.print("{} {s}", .{ self.get_amount(), @tagName(self.get_currency()) });
    }
};
