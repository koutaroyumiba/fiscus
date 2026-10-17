const std = @import("std");
pub const AmountError = error{ CommodityMismatch, Overflow };

pub const Kind = enum {
    currency,
    security,
    custom,
};

pub const CommodityId = u32;
pub const Commodity = struct {
    symbol: []const u8,
    name: ?[]const u8,
    kind: Kind,
    scale: u8,
};

pub const Definition = struct {
    symbol: []const u8,
    kind: Kind,
    scale: u8,
    name: ?[]const u8 = null,
};

/// value is the smallest representable unit
pub const Amount = struct {
    value: i64,
    commodity: CommodityId,

    const Self = @This();

    pub fn negate(self: Self) AmountError!Self {
        return Amount{
            .value = try std.math.negate(self.value),
            .commodity = self.commodity,
        };
    }

    pub fn add(self: Self, other: Self) AmountError!Self {
        if (self.commodity != other.commodity) return AmountError.CommodityMismatch;

        return Amount{
            .value = try std.math.add(i64, self.value, other.value),
            .commodity = self.commodity,
        };
    }

    pub fn sub(self: Self, other: Self) AmountError!Self {
        if (self.commodity != other.commodity) return AmountError.CommodityMismatch;

        return Amount{
            .value = try std.math.sub(i64, self.value, other.value),
            .commodity = self.commodity,
        };
    }

    pub fn eql(self: Self, other: Self) bool {
        return (self.commodity == other.commodity) and (self.value == other.value);
    }

    pub fn order(self: Self, other: Self) AmountError!std.math.Order {
        if (self.commodity != other.commodity) return error.CommodityMismatch;

        return std.math.order(self.value, other.value);
    }
};

pub const CatalogError = error{
    DuplicateSymbol,
    InvalidSymbol,
    InvalidScale,
    InvalidName,
    TooManyCommodities,
};

pub const Catalog = struct {
    allocator: std.mem.Allocator,
    commodities: std.ArrayList(Commodity),
    ids_by_symbol: std.StringHashMap(CommodityId),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!Catalog {
        var self = Self{
            .allocator = allocator,
            .commodities = .empty,
            .ids_by_symbol = std.StringHashMap(CommodityId).init(allocator),
        };
        errdefer self.deinit();

        // built-in commodities (follows ISO 4217)
        try self.addBuiltin("AUD", 2);
        try self.addBuiltin("NZD", 2);
        try self.addBuiltin("USD", 2);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.ids_by_symbol.deinit();

        for (self.commodities.items) |commodity| {
            self.allocator.free(commodity.symbol);
            if (commodity.name) |name| {
                self.allocator.free(name);
            }
        }

        self.commodities.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn add(self: *Self, definition: Definition) !CommodityId {
        if (!isValidSymbol(definition.symbol)) {
            return error.InvalidSymbol;
        }

        if (definition.scale > 18) {
            return error.InvalidScale;
        }

        if (self.ids_by_symbol.contains(definition.symbol)) {
            return error.DuplicateSymbol;
        }

        if (definition.name) |name| {
            if (name.len == 0) {
                return error.InvalidName;
            }
        }

        if (self.commodities.items.len > std.math.maxInt(CommodityId)) {
            return error.TooManyCommodities;
        }

        // check for capacity
        // we do this first to prevent partial updates :D
        try self.commodities.ensureUnusedCapacity(self.allocator, 1);
        try self.ids_by_symbol.ensureUnusedCapacity(1);

        const owned_symbol = try self.allocator.dupe(u8, definition.symbol);
        errdefer self.allocator.free(owned_symbol);
        var owned_name: ?[]u8 = null;
        errdefer if (owned_name) |name| {
            self.allocator.free(name);
        };
        if (definition.name) |name| {
            owned_name = try self.allocator.dupe(u8, name);
        }

        const id: CommodityId = @intCast(self.commodities.items.len);
        self.commodities.appendAssumeCapacity(.{
            .symbol = owned_symbol,
            .name = owned_name,
            .kind = definition.kind,
            .scale = definition.scale,
        });

        self.ids_by_symbol.putAssumeCapacityNoClobber(owned_symbol, id);
        return id;
    }

    pub fn find(self: *const Self, symbol: []const u8) ?CommodityId {
        return self.ids_by_symbol.get(symbol);
    }

    pub fn get(self: *const Self, id: CommodityId) ?Commodity {
        const index = std.math.cast(usize, id) orelse return null;

        if (index >= self.commodities.items.len) {
            return null;
        }

        return self.commodities.items[index];
    }

    pub const ParseAmountError = error{
        UnknownCommodity,
        InvalidAmount,
        TooMuchPrecision,
        Overflow,
    };

    pub fn parseAmount(self: *const Self, number: []const u8, symbol: []const u8) !Amount {
        const commodity_id = self.find(symbol) orelse return error.UnknownCommodity;

        const commodity = self.get(commodity_id).?;
        const value = try parseDecimal(number, commodity.scale);

        return .{
            .value = value,
            .commodity = commodity_id,
        };
    }

    pub fn writeAmountValue(self: *const Self, writer: *std.Io.Writer, amount: Amount) !void {
        const item = self.get(amount.commodity) orelse return error.UnknownCommodity;
        try writeScaledValue(writer, amount.value, item.scale);
    }

    pub fn writeAmount(self: *const Self, writer: *std.Io.Writer, amount: Amount) !void {
        const item = self.get(amount.commodity) orelse return error.UnknownCommodity;
        try writeScaledValue(writer, amount.value, item.scale);
        try writer.print(" {s}", .{item.symbol});
    }

    // === PRIVATE HELPERS ===
    fn writeScaledValue(writer: *std.Io.Writer, value: i64, scale: u8) !void {
        const magnitude: u64 = @abs(value);

        var factor: u64 = 1;
        for (0..@as(usize, scale)) |_| {
            factor *= 10;
        }

        const whole = magnitude / factor;
        const fractional = magnitude % factor;

        if (value < 0) {
            try writer.writeByte('-');
        }

        try writer.print("{d}", .{whole});

        if (scale > 0) {
            try writer.writeByte('.');

            var divisor = factor / 10;
            while (divisor > 0) : (divisor /= 10) {
                const digit: u8 = @intCast((fractional / divisor) % 10);
                try writer.writeByte('0' + digit);
            }
        }
    }

    fn isValidSymbol(symbol: []const u8) bool {
        if (symbol.len == 0 or symbol.len > 32) {
            return false;
        }

        if (!isUpper(symbol[0])) {
            return false;
        }

        for (symbol[1..]) |c| {
            const valid = isUpper(c) or (c >= '0' and c <= '9') or c == '.' or c == '_' or c == '-';

            if (!valid) {
                return false;
            }
        }

        return true;
    }

    fn isUpper(char: u8) bool {
        return char >= 'A' and char <= 'Z';
    }

    fn parseDecimal(text: []const u8, scale: u8) !i64 {
        if (text.len == 0) {
            return error.InvalidAmount;
        }

        var value: i64 = 0;
        var seen_decimal = false;
        var fractional_digits: u8 = 0;
        var digits: usize = 0;

        for (text) |char| {
            if (char == '.') {
                if (seen_decimal or digits == 0) {
                    return error.InvalidAmount;
                }

                seen_decimal = true;
                continue;
            }

            if (char < '0' or char > '9') {
                return error.InvalidAmount;
            }

            if (seen_decimal) {
                if (fractional_digits == scale) {
                    return error.TooMuchPrecision;
                }

                fractional_digits += 1;
            }

            value = try std.math.mul(i64, value, 10);
            value = try std.math.add(i64, value, @as(i64, char - '0'));
            digits += 1;
        }

        if (seen_decimal and fractional_digits == 0) {
            return error.InvalidAmount;
        }

        while (fractional_digits < scale) : (fractional_digits += 1) {
            value = try std.math.mul(i64, value, 10);
        }

        return value;
    }

    fn addBuiltin(self: *Self, symbol: []const u8, scale: u8) std.mem.Allocator.Error!void {
        _ = self.add(.{ .symbol = symbol, .kind = .currency, .scale = scale }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,

            error.InvalidSymbol,
            error.InvalidScale,
            error.InvalidName,
            error.DuplicateSymbol,
            error.TooManyCommodities,
            => unreachable,
        };
    }
};

test "parse exact commodity amounts" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    const aud = catalog.find("AUD").?;

    try std.testing.expectEqual(
        Amount{ .value = 1000, .commodity = aud },
        try catalog.parseAmount("10", "AUD"),
    );
    try std.testing.expectEqual(
        Amount{ .value = 1020, .commodity = aud },
        try catalog.parseAmount("10.2", "AUD"),
    );
    try std.testing.expectEqual(
        Amount{ .value = 1025, .commodity = aud },
        try catalog.parseAmount("10.25", "AUD"),
    );
    try std.testing.expectEqual(
        Amount{ .value = 1, .commodity = aud },
        try catalog.parseAmount("0.01", "AUD"),
    );
}

test "reject invalid commodity amounts" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    try std.testing.expectError(
        error.InvalidAmount,
        catalog.parseAmount("", "AUD"),
    );
    try std.testing.expectError(
        error.InvalidAmount,
        catalog.parseAmount(".50", "AUD"),
    );
    try std.testing.expectError(
        error.InvalidAmount,
        catalog.parseAmount("10.", "AUD"),
    );
    try std.testing.expectError(
        error.TooMuchPrecision,
        catalog.parseAmount("10.005", "AUD"),
    );
    try std.testing.expectError(
        error.InvalidAmount,
        catalog.parseAmount("-10.00", "AUD"),
    );
    try std.testing.expectError(
        error.InvalidAmount,
        catalog.parseAmount("1e3", "AUD"),
    );
    try std.testing.expectError(
        error.UnknownCommodity,
        catalog.parseAmount("10.00", "BTC"),
    );
}

test "detect amount overflow" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    try std.testing.expectError(
        error.Overflow,
        catalog.parseAmount("92233720368547758.08", "AUD"),
    );
}

test "format exact commodity amounts" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    const aud = catalog.find("AUD").?;

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    try catalog.writeAmount(&output.writer, .{ .value = 1025, .commodity = aud });
    try std.testing.expectEqualStrings("10.25 AUD", output.written());
}

test "format amount value without commodity symbol" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    const aud = catalog.find("AUD").?;

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    try catalog.writeAmountValue(&output.writer, .{ .value = 1025, .commodity = aud });
    try std.testing.expectEqualStrings("10.25", output.written());
}

test "format negative fractional commodity amount" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    const aud = catalog.find("AUD").?;

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    try catalog.writeAmount(&output.writer, .{ .value = -1, .commodity = aud });
    try std.testing.expectEqualStrings("-0.01 AUD", output.written());
}

test "format minimum integer amount" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    const aud = catalog.find("AUD").?;

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    try catalog.writeAmount(&output.writer, .{ .value = std.math.minInt(i64), .commodity = aud });
    try std.testing.expectEqualStrings("-92233720368547758.08 AUD", output.written());
}

test "add a custom named security" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    const id = try catalog.add(.{
        .symbol = "NZX.AIR",
        .kind = .security,
        .scale = 6,
        .name = "Air New Zealand",
    });

    const security = catalog.get(id).?;

    try std.testing.expectEqualStrings("NZX.AIR", security.symbol);
    try std.testing.expectEqualStrings("Air New Zealand", security.name.?);
    try std.testing.expectEqual(Kind.security, security.kind);
    try std.testing.expectEqual(@as(u8, 6), security.scale);
}
