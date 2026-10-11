pub const SourceId = u32;

pub const root_source_id: SourceId = 0;

// offset is zero-based
// line and column is one-based
pub const Location = struct {
    offset: usize,
    line: usize,
    column: usize,
};

// end is exclusive
pub const Span = struct {
    source_id: SourceId = root_source_id,
    start: Location,
    end: Location,
};
