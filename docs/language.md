# Fiscus Language Reference

This document describes the currently implemented version 1 journal format. Fiscus journal files use the `.fiscus` extension.

## File structure

A file contains, in order:

1. Version metadata
2. Journal-name metadata
3. Zero or more source directives
4. Zero or more commodity declarations
5. Zero or more account declarations
6. Zero or more transactions

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

source commodities "commodities.fiscus"
source accounts "accounts.fiscus"
source transactions "transactions"
```

A source path is resolved relative to the root journal. It may identify a single file or a directory.

- A `commodities` source may contain commodity declarations only.
- An `accounts` source may contain account declarations only.
- A `transactions` source may contain transactions only.
- Only the root journal may contain source directives.
- Every sourced file must declare the same journal name as the root.
- Every sourced file has its own supported format version.

Source directories are searched recursively. Fiscus loads regular files ending in `.fiscus` in lexical path order. Hidden files, hidden directories, non-`.fiscus` files, and symbolic links are ignored.

For example:

```text
personal/
├── journal.fiscus
├── commodities.fiscus
├── accounts.fiscus
└── transactions/
    └── 2026/
        ├── 01.fiscus
        └── 02.fiscus
```

Commodity declarations are collected first, followed by account declarations and then transactions. Source directive order therefore does not control commodity or account visibility.

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

### Transaction fields

A transaction may contain metadata fields before its first posting. Fields may appear in any order.

```fiscus
transaction 2026-01-17 "Groceries" {
    id groceries-001
    note "Weekly shared grocery shop"
    tag shared
    tag reimbursable

    debit  expense:food:groceries 82.40 AUD
    credit asset:bank             82.40 AUD
}
```

The supported fields are:

- `id WORD`: an optional stable identity that must be unique across the journal;
- `note STRING`: optional additional context attached to the transaction;
- `tag WORD`: a repeatable machine-readable classification.

`id` and `note` may each appear at most once in a transaction. A note cannot be empty. Tags must be unique within a transaction.

A tag starts with a lowercase ASCII letter. Remaining characters may be lowercase letters, digits, `-`, or `_`. Examples include `shared`, `reimbursable`, and `tax-deductible`.

Transaction fields must precede all postings. Once the first posting appears, no further transaction fields are allowed.

## Postings

```fiscus
debit expense:food:groceries 82.40 AUD
```

A posting contains:

1. `debit` or `credit`;
2. a declared account name;
3. a positive decimal amount;
4. a built-in or declared commodity symbol.

Posting amounts cannot use signs, commas, or scientific notation. Zero amounts are rejected.

## Commodities and precision

AUD, NZD, and USD are built in with scale 2. Journals may declare additional currencies, securities, and custom units:

```fiscus
commodity NZX.AIR security scale 6 "Air New Zealand"
commodity BTC custom scale 8 "Bitcoin"
commodity JPY currency scale 0 "Japanese yen"
```

The declaration grammar is:

```text
commodity SYMBOL KIND scale INTEGER [DISPLAY_NAME]
```

`KIND` is `currency`, `security`, or `custom`. Scale is the number of fractional decimal places and must be between 0 and 18. For example, `10.25 AUD` is stored exactly as 1,025 atomic units.

A symbol starts with an uppercase ASCII letter. Remaining characters may be uppercase letters, digits, `.`, `_`, or `-`, with a maximum length of 32 bytes. Symbols must be unique and cannot redeclare a built-in commodity.

The optional display name is a non-empty quoted string. It is descriptive only: postings use the symbol, and display names do not need to be unique.

A journal may use multiple commodities, and an account may have a separate balance in each. Every individual transaction must currently use and balance in exactly one commodity. Declaring a security therefore supports exact security quantities, but a purchase involving both security units and cash still requires the planned multi-commodity valuation model.

## Validation

A valid journal requires:

- format version 1;
- a non-empty journal name;
- syntactically valid, unique commodities;
- commodity scales from 0 through 18;
- non-empty optional commodity display names;
- syntactically valid, unique accounts;
- valid calendar dates;
- declared posting accounts;
- known commodities;
- valid commodity precision;
- positive posting amounts;
- at least two postings per transaction;
- equal debit and credit totals in one commodity;
- unique explicit transaction IDs;
- non-empty transaction notes;
- syntactically valid, unique tags within each transaction;
- no repeated singleton transaction fields;
- matching journal names across a workspace;
- role-appropriate contents in sourced files;
- source directives only in the root journal.

All amount arithmetic is checked for integer overflow.

## Strings

Journal names, transaction narrations, and transaction notes are surrounded by double quotes. Narrations and notes are optional. Escape sequences and multiline strings are not currently supported.

## Planned syntax

The following concepts are planned but are not part of version 1 as currently implemented:

- price and exchange-rate annotations;
- typed external references and transaction links;
- account opening and closing dates.
