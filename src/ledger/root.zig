const core = @import("core/root.zig");
const journal = @import("journal.zig");

// *** CORE STUFF *** //
pub const AmountError = core.AmountError;
pub const CatalogError = core.CatalogError;
pub const DateError = core.DateError;

pub const CommodityKind = core.CommodityKind;
pub const CommodityId = core.CommodityId;
pub const Commodity = core.Commodity;
pub const Amount = core.Amount;
pub const Catalog = core.Catalog;
pub const Date = core.Date;

// *** JOURNAL STUFF *** //
pub const Journal = journal.Journal;

pub const Direction = journal.Direction;
pub const AccountIndex = journal.AccountIndex;
pub const AccountType = journal.AccountType;
pub const TransactionIndex = journal.TransactionIndex;
pub const Transaction = journal.Transaction;

pub const isValidAccountPrefix = journal.isValidAccountPrefix;
pub const matchesAccountPrefix = journal.matchesAccountPrefix;

test {
    _ = core;
    _ = journal;
}
