# Fiscus Language Reference

This document describes the currently implemented version 1 journal format. Fiscus journal files use the `.fiscus` extension.

## File structure

A file contains, in order:

1. Version metadata
2. Journal-name metadata
3. Zero or more account declarations
4. Zero or more transactions

```text
meta version 1
meta journal "personal"

account asset:bank

transaction 2026-01-01 "Opening balance" {
    debit  asset:bank               1000.00 AUD
    credit equity:opening-balances 1000.00 AUD
}
```

Whitespace and blank lines are insignificant. A `#` starts a comment that continues to the end of the line.

## Metadata

Both metadata entries are required and must appear first in this order:

```fiscus
meta version 1
meta journal "personal"
```

Only format version `1` is supported. Journal names are quoted strings and cannot be empty.

## Accounts

```fiscus
account asset:bank:example-bank:au:everyday
```

An account name consists of colon-separated components. Each component:

- starts with a lowercase ASCII letter;
- may continue with lowercase letters, digits, `-`, or `_`;
- cannot be empty.

The first component determines the account type and must be one of:

```text
asset
liability
equity
income
expense
```

Accounts must be declared before transactions and cannot be declared more than once. An account may hold balances in more than one commodity.

## Transactions

```fiscus
transaction 2026-01-17 "Groceries" {
    debit  expense:food:groceries 82.40 AUD
    credit asset:bank             82.40 AUD
}
```

A transaction contains:

- an ISO 8601 calendar date in `YYYY-MM-DD` form;
- a quoted description;
- at least two postings.

An optional stable ID may follow the description:

```fiscus
transaction 2026-01-17 "Groceries" id groceries-001 {
```

Explicit transaction IDs must be non-empty and unique within the journal.

## Postings

```fiscus
debit expense:food:groceries 82.40 AUD
```

A posting contains:

1. `debit` or `credit`;
2. a declared account name;
3. a positive decimal amount;
4. a built-in commodity code.

Posting amounts cannot use signs, commas, or scientific notation. Zero amounts are rejected.

## Commodities and precision

The currently supported commodities are:

| Code | Scale |
|---|---:|
| AUD | 2 |
| NZD | 2 |
| USD | 2 |

Scale is the number of fractional decimal places. For example, `10.25 AUD` is stored exactly as 1,025 atomic units.

A journal may use multiple commodities, and an account may have a separate balance in each. Every individual transaction must currently use and balance in exactly one commodity.

## Validation

A valid journal requires:

- format version 1;
- a non-empty journal name;
- syntactically valid, unique accounts;
- valid calendar dates;
- declared posting accounts;
- known commodities;
- valid commodity precision;
- positive posting amounts;
- at least two postings per transaction;
- equal debit and credit totals in one commodity;
- unique explicit transaction IDs.

All amount arithmetic is checked for integer overflow.

## Strings

Journal names and transaction descriptions are surrounded by double quotes. Escape sequences and multiline strings are not currently supported.

## Planned syntax

The following concepts are planned but are not part of version 1 as currently implemented:

- custom commodity and security declarations;
- price and exchange-rate annotations;
- transaction metadata and tags;
- account opening and closing dates;
- includes or imports.
