# Fiscus Syntax Reference

This document describes the syntax of `fiscus` version 1 journal format. Fiscus journal files use the `.fiscus` extension.

## Quick Start

A file contains, in order

1. Version metadata (required)
2. Journal name metadata (required)
3. Zero or more source directives
4. Zero or more commodity declarations
5. Zero or more account declarations
6. Zero or more transactions

```fiscus
meta version VERSION-NUMBER
meta journal "JOURNAL-NAME"

source commodities "COMMODITY-FILE"
source accounts "ACCOUNT-FILE"
source transactions "TRANSACTION-FOLDER"

commodity SYMBOL KIND scale INTEGER ["DISPLAY_NAME"]

account ACCOUNT [commodity SYMBOL]

txn DATE ["NARRATION"] {
    [id ID]
    [note "NOTE"]
    [tag TAG]

    + ACCOUNT VALUE [COMMODITY] [@@ VALUE COMMODITY]
    - ACCOUNT VALUE [COMMODITY]
}
```

Whitespace and blank lines are insignificant. A `#` starts a comment that continues to the end of the line.

## Metadata

Both metadata entries (version and name) are required and must appear first in this order:

```fiscus
meta version VERSION-NUMBER
meta journal "JOURNAL-NAME"

meta version 1
meta journal "personal"
```

Currently, only format version 1 is supported. Journal names are quoted strings and cannot be empty. Every file in a workspace carries its own metadata. This allows individual files in the workspace to have different syntax versions which should make migrations easier. It also prevents files from another journal being included accidentally.

## Sources

A root journal may import additional files with typed source directives:

```fiscus
source commodities "COMMODITY-FILE"
source accounts "ACCOUNT-FILE"
source transactions "TRANSACTION-FOLDER"

source commodities "commodities.fiscus"
source accounts "accounts.fiscus"
source transactions "transactions"
```

Source directories are searched recursively. Fiscus loads regular files ending in `.fiscus` in lexical path order. Hidden files, hidden directories, non-`.fiscus` files, and symbolic links are ignored.

A source path is resolved relative to the root journal. It may identify a single file or a directory.

- a `commodities` source may contain commodity declarations only
- an `accounts` source may contain account declarations only
- a `transactions` source may contain transactions only
- only the root journal may contain source directives
- every sourced file must declare the same journal name as the root
- every sourced file has its own supported format version

Example workplace:

```
personal/
    journal.fiscus
    commodities.fiscus
    accounts.fiscus
    transactions/
        2026/
            01.fiscus
            02.fiscus
```

Single-file journals are still valid and do not require source directives.

## Commodities

Currently, AUD, NZD and USD are built-in commodities all with scale 2. Journals may declare additional currencies, securities, and custom units.

```fiscus
commodity SYMBOL KIND scale INTEGER ["DISPLAY_NAME"]

commodity NZX.AIR security scale 6 "Air New Zealand"
commodity BTC custom scale 8 "Bitcoin"
commodity JPY currency scale 0 "Japanese Yen"
```

`KIND` can be `currency`, `security`, or `custom`. Scale is the number of fractional decimal places and must be between 0 and 18. For example, `10.25 AUD` is internally stored as 1025 atomic units (scale 2).

The optional `DISPLAY_NAME` is a non-empty quoted string. It is descriptive only: postings use the symbol and display names do not need to be unique.

A journal may use multiple commodities, and an account may have a separate balance in each. A transaction may combines commodities when `@@` annotations give every posting one common balancing commodity. Account balances always retain native posting quantities rather than their transaction valuations.

## Accounts

```fiscus
account ACCOUNT [commodity SYMBOL]

account asset:bank:example-bank:au:everyday commodity AUD
```

An account may optionally declare a fixed commodity with `commodity SYMBOL`. The symbol must be a built-in or a declared commodity. Fixed-commodity accounts accept only that commodity and allow postings to omit it. Accounts without a fixed commodity may hold multiple commodities, and every posting to them must state its commodity explicitly.

An account name consists of colon-separated components. The first component must be one of the account types listed below. Each remaining component starts and ends with a lowercase ASCII letter or digit, may contain lowercase letters, digits, `-`, or `_`, and cannot be empty. This permits numeric components such as `2026`, but not components with dangling separators such as `stuff-` or `stuff_`.

The first component determines the account type and must be one of:
- asset
- liability
- equity
- income
- expense

Accounts must be declared before transactions and cannot be declared more than once. An account may hold balances in more than one commodity.

```text
asset:<category>[:<institution>[:<jurisdiction>[:<account>[:<subaccount>]]]]
liability:<category>[:<institution>[:<jurisdiction>[:<account>[:<subaccount>]]]]
income:<category>:<source>[:<detail>]
expense:<category>[:<subcategory>]
equity:<category>
```

```fiscus
account asset:bank:commbank:au:everyday
account liability:credit-card:amex:au:platinum
account equity:opening-balances
account income:employment:acme:salary
account expense:food:groceries
```

## Transactions

```fiscus
txn DATE ["NARRATION"] {
    [id ID]
    [note "NOTE"]
    [tag TAG]

    + ACCOUNT VALUE [COMMODITY] [@@ VALUE COMMODITY]
    - ACCOUNT VALUE [COMMODITY]
}

txn 2026-01-17 "Groceries" {
    id groceries-001
    note "yummy cucumber"
    tag shared

    + expense:food:groceries  82.40 AUD
    - asset:bank              82.40 AUD
}

# transaction with required fields only
txn 2026-01-17 {
    debit   expense:food:groceries  82.40 NZD
    credit  asset:bank              82.40 NZD
}

txn 2026-01-17 {
    + expense:food:groceries  82.40 NZD
    - asset:bank              82.40 NZD
}
```

`txn` is the officially recommended keyword. The longer `transaction` spelling is deprecated but accepted for compatibility reasons.

A transaction contains:
- an ISO 8601 calendar date in `YYYY-MM-DD` form;
- an optional quoted narration;
- at least two postings

The supported transaction fields are:
- `id WORD`: an optional stable identity that must be unique across the journal;
- `note STRING`: optional additional context attached to the transaction;
- `tag WORD`: a repeatable machine-readable classification;

`id` and `note` may each appear at most once in a transaction. A note cannot be empty. Tags must be unique within a transaction.

Transaction fields must come before all postings. Once the first posting appears, no further transaction fields are allowed.

## Postings

```fiscus
(+ | - | debit | credit) ACCOUNT AMOUNT [COMMODITY] [@@ TOTAL_AMOUNT TOTAL_COMMODITY]

+ asset:broker:nzx:shares 10.000000 NZX.AIR @@ 7.80 NZD
```

A posting contains:
1. a direction: `+` or `debit` for a debit, `-` or `credit` for a credit;
2. a declared account name;
3. a positive decimal amount;
4. a built-in or declared commodity symbol, unless inferred from the account;
5. an optional conversion.

`+` and `-` are direction markers, not signs on the amount. They do not mean
that an account's natural balance increases or decreases; for example, a `-`
credit posting increases an income account.

The commodity may be omitted only when the account declares a fixed commodity. An explicitly written commodity on a fixed-commodity account must match its declaration.

Posting amounts cannot use signs, commas, or scientific notation. Zero amounts are also rejected.

`@@` records the total value of the native amount; it is not a per-unit price. In the above example, 10 `NZX.AIR` is worth 7.80 `NZD` in total.
