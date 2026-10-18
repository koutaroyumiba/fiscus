const std = @import("std");

const Allocator = std.mem.Allocator;
const mod = struct {
    const commodity = @import("commodity.zig");
};

const CommodityId = mod.commodity.CommodityId;
const Commodity = mod.commodity.Commodity;

const CatalogError = error{
    DuplicateSymbol,
    InvalidSymbol,
    InvalidScale,
    InvalidName,
    TooManyCommodities,
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
        try self.addBuiltinCurrnecy("VND", 2);

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

    pub fn addCommodity(self: *Catalog, new_commodity: Commodity) !CommodityId {
        // validate first
        if (isValidCommoditySymbol(new_commodity.symbol)) return error.InvalidSymbol;
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
        _ = self.add(.{
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
};

// invariants for commodity symbols:
// - 0 < symbol.len <= 32
// - starts with a uppercase letter
// - followed by any of [A-Z][0-9][._-]
pub fn isValidCommoditySymbol(symbol: []const u8) bool {
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

// === WRITERS ===

/// writes (value:1234 scale:2) -> 12.34
pub fn writeScaledValue(writer: *std.Io.Writer, value: i64, scale: u8) !void {
    const magnitude: u64 = @abs(value);
    var factor: u64 = 1;
    for (0..@as(usize, scale)) |_| {
        factor *= 10;
    }

    const whole = magnitude / factor;
    const fractional = magnitude % 10;

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

// === PRIVATE HELPERS ===

fn isUpper(char: u8) bool {
    return char >= 'A' and char <= 'Z';
}
