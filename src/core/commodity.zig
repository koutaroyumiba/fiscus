const std = @import("std");

pub const AmountError = error{
    CommodityMismatch,
    Overflow,
};

/// Type of Commodity
pub const Kind = enum {
    currency,
    security,
    custom,
};

pub const CommodityId = u32;

pub const Commodity = struct {
    kind: Kind,
    symbol: []const u8,
    scale: u8,
    name: ?[]const u8,
};

pub const Amount = struct {
    value: i64,
    commodity: CommodityId,

    // === ARITHMETIC OPERATIONS ===
    pub fn negate(self: Amount) AmountError!Amount {
        return Amount{
            .value = try std.math.negate(self.value),
            .commodity = self.commodity,
        };
    }

    pub fn add(self: Amount, other: Amount) AmountError!Amount {
        if (self.commodity != other.commodity) {
            return AmountError.CommodityMismatch;
        }

        return Amount{
            .value = try std.math.add(i64, self.value, other.value),
            .commodity = self.commodity,
        };
    }

    pub fn sub(self: Amount, other: Amount) AmountError!Amount {
        if (self.commodity != other.commodity) {
            return AmountError.CommodityMismatch;
        }

        return Amount{
            .value = try std.math.sub(i64, self.value, other.value),
            .commodity = self.commodity,
        };
    }

    // === COMPARISON OPERATIONS ===
    pub fn eql(self: Amount, other: Amount) bool {
        return (self.commodity == other.commodity) and (self.value == other.value);
    }

    pub fn order(self: Amount, other: Amount) AmountError!std.math.Order {
        if (self.commodity != other.commodity) {
            return error.CommodityMismatch;
        }

        return std.math.order(self.value, other.value);
    }
};
