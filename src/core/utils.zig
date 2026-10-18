const std = @import("std");

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
