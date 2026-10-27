<div align="center">

# fiscus

**A Complete Personal Financial Toolkit, powered by Zig**

[![Status: Experimental](https://img.shields.io/badge/status-experimental-orange?style=flat-square)](#status)
[![Zig](https://img.shields.io/badge/Zig-0.17.0-F7A41D?style=flat-square&logo=zig&logoColor=white)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-2ea44f?style=flat-square)](LICENSE)

</div>

> [!WARNING]
> Fiscus is still experimental. The file format may still undergo breaking changes.

> Required Zig version: **0.17.0**

## Introduction

This all started when I wanted to start tracking my finances... I felt like spreadsheets weren't enough for me (even though I definitely did not use 100% of its capabilities) and wanted to have everything in a program so that I can do whatever analysis I want to do on it.

Then, I came across [TigerBeetle](https://github.com/tigerbeetle/tigerbeetle) while learning [Zig](https://ziglang.org/) and it was so cool, inspiring me to make my own financial 'system' in Zig.

While researching, I learnt about double-entry bookkeeping as well as examples of software that were simliar to what I wanted: [Beancount](https://beancount.github.io/docs/). Taking inspiration from all of these things, I decided (for no reason at all) to make my own DSL (`.fiscus`) to track my finances!

It was a lot of fun to think about the syntax for this language and how to go about supporting some common financial activities that people go through :D

## Browser viewer

A private, dependency-free journal viewer is available in [`web/`](web/). It parses files entirely in the browser and provides transaction search, account/tag filters, account balances, and visual reports.

```sh
python3 -m http.server 8080 -d web
# open http://localhost:8080
```

Drop a complete Fiscus workspace folder onto the viewer (nested transaction folders are supported), choose a folder, or select individual `.fiscus` files together. No journal data is uploaded or persisted.

## Current Features (implemented)

```sh
# validate ./journal.fiscus
fis check

# or provide a journal explicitly
fis check examples/personal.fiscus

# print account balances (defaults to ./journal.fiscus)
fis balance

# or provide a journal explicitly
fis balance examples/personal.fiscus

# summarize an account and all of its descendants
fis balance examples/personal.fiscus --prefix asset:bank

# show the largest child balances first
fis balance examples/personal.fiscus --prefix asset:bank --sort amount

# aggregate only transactions with an exact tag
fis balance examples/personal.fiscus --tag trip:japan --prefix expense

# aggregate a tag namespace (matches trip and trip:*)
fis balance examples/personal.fiscus --tag-prefix trip --prefix expense --sort amount

# inspect transactions in ./journal.fiscus
fis inspect

# or provide a journal explicitly
fis inspect examples/personal.fiscus

# inspect a transaction by ID
fis inspect examples/personal.fiscus --id salary-2026-01

# combine filters (date bounds are inclusive)
fis inspect examples/personal.fiscus --account asset:bank:example-bank:au:everyday --from 2026-01-01 --to 2026-01-31
fis inspect examples/personal.fiscus --tag income

# show account changes and running balances
fis inspect examples/personal.fiscus --account asset:bank:example-bank:au:everyday --running-balance
```

Running balances use the account's natural accounting sign and include earlier transactions when `--from` filters the displayed entries.

## Journal format (proposed - still experimental)

Fiscus supports both single-file journals and multi-file workspaces.

See [syntax.md](docs/syntax.md) for the `.fiscus` syntax spec.

```fiscus
meta version 1
meta journal "personal"

account asset:bank commodity AUD
account equity:opening-balances commodity AUD
account income:salary commodity AUD
account expense:food:groceries commodity AUD

txn 2026-01-01 "Opening balance" {
    + asset:bank               1000.00
    - equity:opening-balances 1000.00
}

txn 2026-01-15 "Salary" {
    id salary-2026-01
    note "Monthly salary payment"
    tag income

    + asset:bank    3000.00
    - income:salary 3000.00
}
```

Larger journals can keep accounts and transactions in separate sources:

```fiscus
meta version 1
meta journal "personal"

source commodities "commodities.fiscus"
source accounts "accounts.fiscus"
source transactions "transactions"
```

Commodity, account, and transaction sources may be files or recursively searched directories of `.fiscus` files. Every sourced file carries its own version and journal metadata. See [`examples/workspace/`](examples/workspace/) for a complete layout.

Account type is inferred from the first component of its name. Supported roots are:

- `asset`
- `liability`
- `equity`
- `income`
- `expense`

Accounts may optionally declare a fixed commodity with `commodity SYMBOL`. Postings to fixed-commodity accounts can omit the repeated symbol; unrestricted accounts continue to support multiple commodities.

`txn` is the canonical transaction keyword, while `transaction` remains accepted for compatibility. Posting directions may use concise `+` (debit) and `-` (credit) markers; the longer words remain accepted. Transaction narrations and metadata are optional. A transaction body may contain one unique `id`, one quoted `note`, and any number of unique machine-readable `tag` fields before its postings.

See [`docs/language.md`](docs/language.md) for the implemented grammar and validation rules, and [`docs/glossary.md`](docs/glossary.md) for accounting terminology.

## Current limitations

- Multi-commodity transactions require explicit exact `@@` total valuations in one balancing commodity.
- Securities can be declared, counted, purchased, and sold, but market prices, tax lots, cost basis, and gains are not yet supported.
- AUD, NZD, and USD are built in; other currencies must currently be declared explicitly.
- Strings do not support escapes or newlines.
- Account lifecycle dates, typed external references, transaction links, and file editing are not supported.
- The only report currently implemented is account balances.

## Project structure

```text
src/
    main.zig            CLI process entry point
    cli.zig             command handling and file I/O
    root.zig            public module exports

    commodity.zig       commodities and exact amounts
    time.zig            date validation and parsing
    accounting.zig      journal domain model and validation
    reports.zig         derived account balances

    loader.zig          single-source loading pipeline
    workspace.zig       multi-file workspace loading
    source_manager.zig  source ownership and identity
    decoder.zig         AST-to-journal conversion
    diagnostics.zig     source diagnostic rendering

    lang/               .fiscus language implementation
        source.zig
        lexer.zig
        ast.zig
        parser.zig
```

## Roadmap

- [ ] Account Lifetimes - (`open`, `close` keyword/field on accounts)
- [ ] Balance Assertions - `balance` keyword to assert (or maybe just have `assert`?)
- [ ] Price Observation - useful for stocks or maybe even currencies (cost basis)
- [ ] Event - equivalent to a note attached to a date (useful for location/employer?)
- [ ] Links - for relevant documents? (`link` keyword?)
- [ ] Exporting/Importing from common file formats (maybe JSON?)
- [ ] Error codes with diagnostics

```text
error[FIS1001]: unsupported Fiscus language version 3
error[FIS1104]: invalid calendar date 2025-02-29
error[FIS1201]: unknown account Expenses:Groceris
error[FIS1202]: account Assets:Checking is closed on 2025-03-01
error[FIS1204]: posting amount must be greater than zero
error[FIS1205]: amount has 3 fractional digits; journal scale is 2
error[FIS1301]: duplicate transaction ID "txn-001"
error[FIS1401]: balance assertion failed by 25.00 NZD
```

## License

Licensed under the [MIT License](LICENSE).
