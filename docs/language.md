# Fiscus Language Reference

This document describes the currently implemented version 1 journal format. Fiscus journal files use the `.fiscus` extension.

## File structure

A file contains, in order:

1. Version metadata
2. Journal-name metadata
3. Zero or more source directives
4. Zero or more account declarations
5. Zero or more transactions

```text
meta version 1
meta journal "personal"

account asset:bank
account equity:opening-balances

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

Every file in a workspace carries its own metadata. This lets Fiscus identify the syntax version of historical files independently and prevents files from another journal being included accidentally.

## Sources

A root journal may compose additional files with typed source directives:

```fiscus
meta version 1
meta journal "personal"

source accounts "accounts.fiscus"
source transactions "transactions"
```

A source path is resolved relative to the root journal. It may identify a single file or a directory.

- An `accounts` source may contain account declarations but not transactions.
- A `transactions` source may contain transactions but not account declarations.
- Only the root journal may contain source directives.
- Every sourced file must declare the same journal name as the root.
- Every sourced file has its own supported format version.

Source directories are searched recursively. Fiscus loads regular files ending in `.fiscus` in lexical path order. Hidden files, hidden directories, non-`.fiscus` files, and symbolic links are ignored.

For example:

```text
personal/
├── journal.fiscus
├── accounts.fiscus
└── transactions/
    └── 2026/
        ├── 01.fiscus
        └── 02.fiscus
```

Account declarations from the root and all account sources are collected before any transactions are resolved. Source directive order therefore does not control account visibility.

Single-file journals remain valid and do not require source directives.

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
- an optional quoted narration;
- at least two postings.

The narration may be omitted:

```fiscus
transaction 2026-01-17 {
    debit  expense:food:groceries 82.40 AUD
    credit asset:bank             82.40 AUD
}
```

An optional stable ID may appear inside the transaction body before any postings:

```fiscus
transaction 2026-01-17 "Groceries" {
    id groceries-001

    debit  expense:food:groceries 82.40 AUD
    credit asset:bank             82.40 AUD
}
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
- unique explicit transaction IDs;
- matching journal names across a workspace;
- role-appropriate contents in sourced files;
- source directives only in the root journal.

All amount arithmetic is checked for integer overflow.

## Strings

Journal names and transaction narrations are surrounded by double quotes. Transaction narrations are optional. Escape sequences and multiline strings are not currently supported.

## Planned syntax

The following concepts are planned but are not part of version 1 as currently implemented:

- custom commodity and security declarations;
- price and exchange-rate annotations;
- transaction metadata and tags;
- account opening and closing dates.
