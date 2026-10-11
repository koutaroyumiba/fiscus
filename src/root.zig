pub const accounting = @import("accounting.zig");
pub const commodity = @import("commodity.zig");
pub const decoder = @import("decoder.zig");
pub const diagnostics = @import("diagnostics.zig");
pub const lang = @import("lang/root.zig");
pub const loader = @import("loader.zig");
pub const money = @import("money.zig");
pub const time = @import("time.zig");

test {
    _ = accounting;
    _ = commodity;
    _ = decoder;
    _ = diagnostics;
    _ = lang;
    _ = loader;
    _ = money;
    _ = time;
}
