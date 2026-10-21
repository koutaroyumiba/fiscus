pub const application = @import("application.zig");
pub const core = @import("core/root.zig");
pub const decoder = @import("decoder.zig");
pub const diagnostics = @import("diagnostics.zig");
pub const lang = @import("lang/root.zig");
pub const ledger = @import("ledger/root.zig");
pub const loader = @import("loader.zig");
pub const reports = @import("reports.zig");
pub const source_manager = @import("source_manager.zig");
pub const workspace = @import("workspace.zig");

test {
    _ = application;
    _ = core;
    _ = decoder;
    _ = diagnostics;
    _ = lang;
    _ = ledger;
    _ = loader;
    _ = reports;
    _ = source_manager;
    _ = workspace;
}
