pub const AmountError = error{
    CommodityMismatch,
    Overflow,
};

pub const CatalogError = error{
    DuplicateSymbol,
    InvalidSymbol,
    InvalidScale,
    InvalidName,
    TooManyCommodities,
};
