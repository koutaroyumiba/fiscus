const journal = @import("journal.zig");

pub const Core = @import("core/root.zig");

pub const Journal = journal.Journal;

pub const Direction = journal.Direction;
pub const AccountIndex = journal.AccountIndex;
pub const AccountType = journal.AccountType;
pub const TransactionIndex = journal.TransactionIndex;
pub const Transaction = journal.Transaction;

pub const isValidAccountPrefix = journal.isValidAccountPrefix;
pub const matchesAccountPrefix = journal.matchesAccountPrefix;

test {
    _ = Core;
    _ = journal;
}
