const std = @import("std");

const Allocator = std.mem.Allocator;
const mod = struct {
    const commodity = @import("commodity.zig");
};

const Amount = mod.commodity.Amount;
const CommodityId = mod.commodity.CommodityId;
const Commodity = mod.commodity.Commodity;

pub const CatalogError = error{
    DuplicateSymbol,
    InvalidSymbol,
    InvalidScale,
    InvalidName,
    TooManyCommodities,
};

pub const ParseAmountError = error{
    UnknownCommodity,
    InvalidAmount,
    TooMuchPrecision,
    Overflow,
};

// CONSTANTS
const MAX_SCALE = 18;

pub const Catalog = struct {
    allocator: Allocator,
    commodities: std.ArrayList(Commodity),
    ids_by_symbol: std.StringHashMap(CommodityId),

    pub fn init(allocator: Allocator) Allocator.Error!Catalog {
        var self = Catalog{
            .allocator = allocator,
            .commodities = .empty,
            .ids_by_symbol = std.StringHashMap(CommodityId).init(allocator),
        };
        errdefer self.deinit();

        // builtin commodities (follows ISO 4217)
        try self.addBuiltinCurrency("AUD", 2);
        try self.addBuiltinCurrency("HKD", 2);
        try self.addBuiltinCurrency("JPY", 0);
        try self.addBuiltinCurrency("NZD", 2);
        try self.addBuiltinCurrency("USD", 2);
        try self.addBuiltinCurrency("VND", 0);

        return self;
    }

    pub fn deinit(self: *Catalog) void {
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

    pub fn idFromSymbol(self: *const Catalog, symbol: []const u8) ?CommodityId {
        return self.ids_by_symbol.get(symbol);
    }

    pub fn commodityFromId(self: *const Catalog, id: CommodityId) ?Commodity {
        const index = std.math.cast(usize, id) orelse return null;

        if (index >= self.commodities.items.len) {
            return null;
        }

        return self.commodities.items[index];
    }

    pub fn addCommodity(self: *Catalog, new_commodity: Commodity) !CommodityId {
        // validate first
        if (!isValidCommoditySymbol(new_commodity.symbol)) return error.InvalidSymbol;
        if (new_commodity.scale > MAX_SCALE) return error.InvalidScale;
        if (self.ids_by_symbol.contains(new_commodity.symbol)) return error.DuplicateSymbol;
        if (new_commodity.name) |name| {
            if (name.len == 0) return error.InvalidName;
        }
        if (self.commodities.items.len > std.math.maxInt(CommodityId)) return error.TooManyCommodities;

        // check for additions first (prevent partial updates)
        try self.commodities.ensureUnusedCapacity(self.allocator, 1);
        try self.ids_by_symbol.ensureUnusedCapacity(1);

        // dupe the strings
        const owned_symbol = try self.allocator.dupe(u8, new_commodity.symbol);
        errdefer self.allocator.free(owned_symbol);
        var owned_name: ?[]u8 = null;
        errdefer if (owned_name) |name| self.allocator.free(name);
        if (new_commodity.name) |name| {
            owned_name = try self.allocator.dupe(u8, name);
        }

        // create a new ID (assumes no commodities are deleted)
        const id: CommodityId = @intCast(self.commodities.items.len);

        self.commodities.appendAssumeCapacity(.{
            .kind = new_commodity.kind,
            .symbol = owned_symbol,
            .scale = new_commodity.scale,
            .name = owned_name,
        });
        self.ids_by_symbol.putAssumeCapacityNoClobber(owned_symbol, id);

        return id;
    }

    // private because should only be called in `init`
    fn addBuiltinCurrency(self: *Catalog, symbol: []const u8, scale: u8) Allocator.Error!void {
        _ = self.addCommodity(.{
            .kind = .currency,
            .symbol = symbol,
            .scale = scale,
            .name = null,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,

            error.InvalidSymbol,
            error.InvalidScale,
            error.InvalidName,
            error.DuplicateSymbol,
            error.TooManyCommodities,
            => unreachable,
        };
    }

    pub fn parseAmount(self: *const Catalog, number: []const u8, symbol: []const u8) ParseAmountError!Amount {
        const commodity_id = self.idFromSymbol(symbol) orelse return error.UnknownCommodity;
        const commodity = self.commodityFromId(commodity_id).?;
        const value = try parseDecimal(number, commodity.scale);

        return .{
            .value = value,
            .commodity = commodity_id,
        };
    }

    // WRITERS
    pub fn writeAmount(self: *const Catalog, writer: *std.Io.Writer, amount: Amount) !void {
        const commodity = self.commodityFromId(amount.commodity) orelse return error.UnknownCommodity;
        try writeScaledValue(writer, amount.value, commodity.scale);
        try writer.print(" {s}", .{commodity.symbol});
    }

    pub fn writeAmountValue(self: *const Catalog, writer: *std.Io.Writer, amount: Amount) !void {
        const commodity = self.commodityFromId(amount.commodity) orelse return error.UnknownCommodity;
        try writeScaledValue(writer, amount.value, commodity.scale);
    }
};

// === HELPER FUNCTIONS

// invariants for commodity symbols:
// - 0 < symbol.len <= 32
// - starts with a uppercase letter
// - followed by any of [A-Z][0-9][._-]
fn isValidCommoditySymbol(symbol: []const u8) bool {
    if (symbol.len == 0 or symbol.len > 32) {
        return false;
    }

    if (!isUpper(symbol[0])) {
        return false;
    }

    for (symbol[1..]) |c| {
        const valid = isUpper(c) or
            (c >= '0' and c <= '9') or
            c == '.' or c == '_' or c == '-';

        if (!valid) {
            return false;
        }
    }

    return true;
}

fn parseDecimal(text: []const u8, scale: u8) !i64 {
    if (text.len == 0) return error.InvalidAmount;

    var value: i64 = 0;
    var seen_decimal = false;
    var fractional_digits: u8 = 0;
    var digits: usize = 0;

    for (text) |char| {
        if (char == '.') {
            if (seen_decimal or digits == 0) return error.InvalidAmount;

            seen_decimal = true;
            continue;
        }

        if (char < '0' or char > '9') return error.InvalidAmount;

        if (seen_decimal) {
            if (fractional_digits == scale) return error.TooMuchPrecision;

            fractional_digits += 1;
        }

        value = try std.math.mul(i64, value, 10);
        value = try std.math.add(i64, value, @as(i64, char - '0'));
        digits += 1;
    }

    if (seen_decimal and fractional_digits == 0) return error.InvalidAmount;
    while (fractional_digits < scale) : (fractional_digits += 1) {
        value = try std.math.mul(i64, value, 10);
    }

    return value;
}

// === WRITERS ===

/// writes (value:1234 scale:2) -> 12.34
pub fn writeScaledValue(writer: *std.Io.Writer, value: i64, scale: u8) !void {
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

fn isUpper(char: u8) bool {
    return char >= 'A' and char <= 'Z';
}

// === TESTS ===

test "parse exact commodity amounts" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    const aud = catalog.idFromSymbol("AUD").?;

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

    try std.testing.expectError(error.InvalidAmount, catalog.parseAmount("", "AUD"));
    try std.testing.expectError(error.InvalidAmount, catalog.parseAmount(".50", "AUD"));
    try std.testing.expectError(error.InvalidAmount, catalog.parseAmount("10.", "AUD"));
    try std.testing.expectError(error.InvalidAmount, catalog.parseAmount("-10.00", "AUD"));
    try std.testing.expectError(error.InvalidAmount, catalog.parseAmount("1e3", "AUD"));
    try std.testing.expectError(error.TooMuchPrecision, catalog.parseAmount("10.005", "AUD"));
    try std.testing.expectError(error.UnknownCommodity, catalog.parseAmount("10.00", "BTC"));

    // overflow
    try std.testing.expectError(error.Overflow, catalog.parseAmount("92233720368547758.08", "AUD"));
}

test "format exact commodity amounts" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    const aud = catalog.idFromSymbol("AUD").?;

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    try catalog.writeAmount(&output.writer, .{ .value = 1025, .commodity = aud });
    try std.testing.expectEqualStrings("10.25 AUD", output.written());
}

test "format negative fractional commodity amount" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    const aud = catalog.idFromSymbol("AUD").?;

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    try catalog.writeAmount(&output.writer, .{ .value = -1, .commodity = aud });
    try std.testing.expectEqualStrings("-0.01 AUD", output.written());
}

test "format amount value without commodity symbol" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    const aud = catalog.idFromSymbol("AUD").?;

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    try catalog.writeAmountValue(&output.writer, .{ .value = 1025, .commodity = aud });
    try std.testing.expectEqualStrings("10.25", output.written());
}

test "format minimum integer amount" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    const aud = catalog.idFromSymbol("AUD").?;

    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    try catalog.writeAmount(&output.writer, .{ .value = std.math.minInt(i64), .commodity = aud });
    try std.testing.expectEqualStrings("-92233720368547758.08 AUD", output.written());
}

test "add a custom named security" {
    var catalog = try Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    const id = try catalog.addCommodity(.{
        .kind = .security,
        .symbol = "NZX.AIR",
        .scale = 6,
        .name = "Air New Zealand",
    });
    const security = catalog.commodityFromId(id).?;

    try std.testing.expectEqual(mod.commodity.Kind.security, security.kind);
    try std.testing.expectEqualStrings("NZX.AIR", security.symbol);
    try std.testing.expectEqual(@as(u8, 6), security.scale);
    try std.testing.expectEqualStrings("Air New Zealand", security.name.?);
}
