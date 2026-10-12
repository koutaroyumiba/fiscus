# Fiscus Accounting Glossary

Fiscus is based on double-entry accounting. Every financial event is represented by a transaction containing two or more postings.

## Journal

A journal is the complete collection of account declarations and transactions. It may live in one `.fiscus` file or in a workspace composed from several versioned source files.

```fiscus
meta version 1
meta journal "personal"
```

A larger journal can identify separate account and transaction sources:

```fiscus
source accounts "accounts.fiscus"
source transactions "transactions"
```

All files in the workspace use the same journal name.

## Account

An account is a named bucket used to classify value:

```fiscus
account asset:bank
account expense:food:groceries
```

Names are hierarchical. The first component determines the account type:

- `asset`
- `liability`
- `equity`
- `income`
- `expense`

The complete set of accounts is often called the chart of accounts.

## Transaction

A transaction records one dated financial event:

```fiscus
transaction 2026-01-17 "Groceries" {
    debit  expense:food:groceries 82.40 AUD
    credit asset:bank             82.40 AUD
}
```

A transaction may have an optional narration and an explicit unique ID. The ID appears in the body before any postings:

```fiscus
transaction 2026-01-17 "Groceries" {
    id groceries-001

    debit  expense:food:groceries 82.40 AUD
    credit asset:bank             82.40 AUD
}
```

Transactions without a narration or explicit ID are valid.

A transaction may also contain one note and multiple unique tags before its postings:

```fiscus
transaction 2026-01-17 "Groceries" {
    note "Weekly shared grocery shop"
    tag shared
    tag reimbursable

    debit  expense:food:groceries 82.40 AUD
    credit asset:bank             82.40 AUD
}
```

A note preserves additional human-readable context. Tags are short machine-readable labels for classifications that do not naturally belong in the account hierarchy.

## Posting

A posting is one account's side of a transaction:

```fiscus
debit expense:food:groceries 82.40 AUD
```

It has a direction, account, amount, and commodity. Posting amounts are positive; direction is expressed with `debit` or `credit`.

A posting may carry an exact total valuation in another commodity:

```fiscus
debit asset:broker:nzx:shares 10.000000 NZX.AIR @@ 7.80 NZD
```

The account receives `10.000000 NZX.AIR`; `7.80 NZD` is used to balance that transaction. `@@` means total value rather than a per-unit price.

## Debit and credit

Debit and credit are accounting directions, not synonyms for money entering or leaving.

| Account type | Increases with | Decreases with |
|---|---|---|
| Asset | Debit | Credit |
| Expense | Debit | Credit |
| Liability | Credit | Debit |
| Equity | Credit | Debit |
| Income | Credit | Debit |

The side that normally increases an account is its normal balance.

## Account types

### Asset

Something owned or controlled that has value, such as cash or a bank account. Assets increase with debits.

### Liability

An obligation, such as credit-card debt or a loan. Liabilities increase with credits.

### Equity

Residual value after liabilities are deducted from assets. Opening balances commonly use equity to explain value that existed before the journal began.

```fiscus
debit  asset:bank               1000.00 AUD
credit equity:opening-balances 1000.00 AUD
```

### Income

Value earned or received, such as salary or interest. Income increases with credits.

### Expense

Value consumed or spent, such as rent or groceries. Expenses increase with debits.

## Double-entry accounting

Every transaction has at least two postings, and total debits must equal total credits.

```fiscus
debit  expense:food:groceries 82.40 AUD
credit asset:bank             82.40 AUD
```

An unbalanced transaction is invalid:

```fiscus
debit  expense:food:groceries 20.00 AUD
credit asset:bank             19.00 AUD
```

## Accounting equation

The fundamental equation is:

```text
assets - liabilities = equity
```

Including activity over a period:

```text
assets - liabilities = equity + income - expenses
```

## Commodity

A commodity is the unit being measured. AUD, NZD, and USD are built-in currency commodities. Journals may declare additional currencies, securities, and custom units:

```fiscus
commodity NZX.AIR security scale 6 "Air New Zealand"
```

The symbol is the persistent identity used in postings. The optional display name is descriptive and does not need to be unique.

An amount always includes a commodity:

```text
100.00 AUD
50.00 USD
```

Different commodities are tracked as separate balances and cannot be added directly.

## Scale and atomic units

Scale is the supported fractional precision of a commodity. AUD has scale 2, so `10.25 AUD` is represented exactly as 1,025 atomic units. `10.005 AUD` is invalid.

Fiscus stores amounts as integers rather than floating-point values, avoiding binary floating-point rounding errors.

## Balance

An account balance is the net result of its postings. Fiscus reports balances using each account type's normal sign.

For an asset account:

```fiscus
debit  asset:bank 1000.00 AUD
debit  asset:bank 3000.00 AUD
credit asset:bank   82.40 AUD
```

The balance is `3917.60 AUD`.

An account can have independent balances in more than one commodity.

## Opening balance

An opening balance records value that existed before journal tracking began. An equity posting supplies the corresponding accounting source.

## Ledger

A ledger organizes postings by account rather than by transaction. Ledger reports are planned but are not yet implemented.

## Reports

The current `balance` report prints each non-zero account and commodity balance. Balance-sheet, income-statement, cash-flow, and account-ledger reports are planned.

## Planned concepts

Unit prices, market-price history, tax lots, jurisdiction-specific cost basis, and capital gains are not currently implemented. Their eventual syntax and accounting rules remain subject to change.
