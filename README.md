<div align="center">

# fiscus

[![Status: Experimental](https://img.shields.io/badge/status-experimental-orange?style=flat-square)](#status)
[![Zig](https://img.shields.io/badge/Zig-0.17.0-F7A41D?style=flat-square&logo=zig&logoColor=white)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-2ea44f?style=flat-square)](LICENSE)

**A Complete Personal Financial Toolkit, powered by Zig**

</div>

The repository is named `fiscus`; its command-line program is `fis`.

## Status

Fiscus is experimental. Currently, it can parse and validate journals, enforce double-entry accounting, and report natural account balances. The file format may still undergo breaking changes.

Required Zig version: **0.17.0**.

## Current Implementations

```sh
# validate a journal (a .fiscus file)
fis check examples/personal.fiscus

# print account balances
fis balance examples/personal.fiscus
```

## Journal format (proposed - still experimental)

Fiscus supports both single-file journals and multi-file workspaces.

```fiscus
meta version 1
meta journal "personal"

account asset:bank
account equity:opening-balances
account income:salary
account expense:food:groceries

transaction 2026-01-01 "Opening balance" {
    debit  asset:bank               1000.00 AUD
    credit equity:opening-balances 1000.00 AUD
}

transaction 2026-01-15 "Salary" {
    id salary-2026-01
    note "Monthly salary payment"
    tag income

    debit  asset:bank    3000.00 AUD
    credit income:salary 3000.00 AUD
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

Transaction narrations and metadata are optional. A transaction body may contain one unique `id`, one quoted `note`, and any number of unique machine-readable `tag` fields before its postings.

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

## Motivation

- [Beancount](https://beancount.github.io/docs/)
- [TigerBeetle](https://github.com/tigerbeetle/tigerbeetle)

## License

Licensed under the [MIT License](LICENSE).
