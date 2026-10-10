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
    kind: Kind,
    scale: u8,
    quote: ?CommodityId,
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
    UnknownQuoteCommodity,
    TooManyCommodities,
};

pub const Catalog = struct {
    allocator: std.mem.Allocator,
    commodities: std.ArrayList(Commodity),
    ids_by_symbol: std.StringHashMap(CommodityId),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Catalog {
        var self = Self{
            .allocator = allocator,
            .commodities = .empty,
            .ids_by_symbol = std.StringHashMap(CommodityId).init(allocator),
        };
        errdefer self.deinit();

        // built-in commodities (follows ISO 4217)
        _ = try self.add("AUD", .currency, 2, null);
        _ = try self.add("NZD", .currency, 2, null);
        _ = try self.add("USD", .currency, 2, null);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.ids_by_symbol.deinit();

        for (self.commodities.items) |commodity| {
            self.allocator.free(commodity.symbol);
        }

        self.commodities.deinit(self.allocator);
        // cool syntax
        self.* = undefined;
    }

    pub fn add(self: *Self, symbol: []const u8, kind: Kind, scale: u8, quote: ?CommodityId) !CommodityId {
        if (!is_valid_symbol(symbol)) {
            return error.InvalidSymbol;
        }

        if (scale > 18) {
            return error.InvalidScale;
        }

        if (self.ids_by_symbol.contains(symbol)) {
            return error.DuplicateSymbol;
        }

        if (quote) |quote_id| {
            if (self.get(quote_id) == null) {
                return error.UnknownQuoteCommodity;
            }
        }

        if (self.commodities.items.len > std.math.maxInt(CommodityId)) {
            return error.TooManyCommodities;
        }

        // check for capacity
        // we do this first to prevent partial updates :D
        try self.commodities.ensureUnusedCapacity(self.allocator, 1);
        try self.ids_by_symbol.ensureUnusedCapacity(1);

        const owned_symbol = try self.allocator.dupe(u8, symbol);
        errdefer self.allocator.free(owned_symbol);

        const id: CommodityId = @intCast(self.commodities.items.len);
        self.commodities.appendAssumeCapacity(.{
            .symbol = owned_symbol,
            .kind = kind,
            .scale = scale,
            .quote = quote,
        });

        self.ids_by_symbol.putAssumeCapacityNoClobber(owned_symbol, id);
        return id;
    }

    pub fn find(self: *const Catalog, symbol: []const u8) ?CommodityId {
        return self.ids_by_symbol.get(symbol);
    }

    pub fn get(self: *const Catalog, id: CommodityId) ?Commodity {
        const index = std.math.cast(usize, id) orelse return null;

        if (index >= self.commodities.items.len) {
            return null;
        }

        return self.commodities.items[index];
    }

    // === PRIVATE HELPERS ===
    fn is_valid_symbol(symbol: []const u8) bool {
        if (symbol.len == 0 or symbol.len > 32) {
            return false;
        }

        if (!is_uppercase_letter(symbol[0])) {
            return false;
        }

        for (symbol[1..]) |c| {
            const valid = is_uppercase_letter(c) or (c >= '0' and c <= '9') or c == '.' or c == '_' or c == '-';

            if (!valid) {
                return false;
            }
        }

        return true;
    }

    fn is_uppercase_letter(char: u8) bool {
        return char >= 'A' and char <= 'Z';
    }
};
