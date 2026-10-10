// offset is zero-based
// line and column is one-based
pub const Location = struct {
    offset: usize,
    line: usize,
    column: usize,
};

// end is exclusive
pub const Span = struct {
    start: Location,
    end: Location,
};
