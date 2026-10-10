<div align="center">

# fiscus

[![Status: Experimental](https://img.shields.io/badge/status-experimental-orange?style=flat-square)](#)
[![Zig](https://img.shields.io/badge/Zig-0.17.0-F7A41D?style=flat-square&logo=zig&logoColor=white)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-2ea44f?style=flat-square)](LICENSE)

**Personal Financial Toolkit, powered by Zig.**

</div>

Repository `fiscus`, CLI: `fis`

Required Zig version: `0.17.0`

## Motivation

- https://beancount.github.io/docs/
- https://github.com/tigerbeetle/tigerbeetle

## Potential Structure (not decided yet...)

```
src/
    main.zig            # process startup: invoke cli
    root.zig            # public accounting module exports

    money.zig           # exact amounts, parsing, formatting, arithmetic
    time.zig            # time utils
    accounting.zig      # accounts, postings, transactions, rules
    journal.zig         # in-memory journal validation and queries

    diagnostics.zig     # diagnostics
    reports.zig         # derived balances and financial reports
    storage.zig         # locking, backups, atomic file replacement
    cli.zig             # command parsing and output formatting

    dsl/
        root.zig
        source.zig
        lexer.zig
        ast.zig
        parser.zig
        lower.zig
```

## License

Licensed under the [MIT License](LICENSE).
