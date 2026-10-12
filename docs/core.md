# Fiscus Core Model

Fiscus uses double-entry accounting with exact, commodity-aware amounts.

## Commodities and amounts

An amount is a scaled integer paired with an internal commodity ID. Floating-point arithmetic is not used.

The built-in commodities are AUD, NZD, and USD, each with scale 2. Journals may declare additional currencies, securities, and custom units with an exact scale and optional display name. A journal may contain multiple commodities, and an account may hold a separate balance in each.

Every individual transaction must currently balance in one commodity. Security quantities can therefore be represented, but purchases involving both security units and cash require the planned price and cost model. Price annotations, currency conversion, cost basis, and gains are not yet implemented.

## Workspaces and sources

A journal may be stored in one file or composed from typed sources:

```fiscus
meta version 1
meta journal "personal"

source commodities "commodities.fiscus"
source accounts "accounts.fiscus"
source transactions "transactions"
```

Every source is a complete versioned `.fiscus` document with matching journal metadata. Commodity sources define units, account sources define the chart of accounts, and transaction sources contain financial events. Directories are discovered recursively and loaded deterministically.

All commodity declarations are decoded before accounts, and all accounts are decoded before transactions, regardless of source order. This preserves global validation while allowing definitions and transaction history to be split into manageable files.

## Accounts

An account's type is inferred from the first component of its name:

```fiscus
account asset:bank:commbank:au:everyday
account liability:credit-card:amex:au:platinum
account equity:opening-balances
account income:employment:acme:salary
account expense:food:groceries
```

Typical structures are:

```text
asset:<category>[:<institution>[:<jurisdiction>[:<account>[:<subaccount>]]]]
liability:<category>[:<institution>[:<jurisdiction>[:<account>[:<subaccount>]]]]
income:<category>:<source>[:<detail>]
expense:<category>[:<subcategory>]
equity:<category>
```

### Naming conventions

1. The top-level component is one of `asset`, `liability`, `equity`, `income`, or `expense`.
2. Components use lowercase letters, digits, hyphens, and underscores.
3. Country and currency identifiers in account names use lowercase ISO-style codes.
4. Names describe stable identities rather than mutable properties.
5. Include a currency component only when it distinguishes a real-world subaccount.
6. Account names do not constrain which commodities the account may hold.

## Transactions and postings

A transaction records a dated event with two or more postings. Posting amounts are positive; `debit` and `credit` represent accounting direction.

A transaction may also have an optional narration, stable ID, note, and machine-readable tags. The note preserves structured context, while tags classify properties that cut across the account hierarchy, such as `shared` or `reimbursable`. Ordinary counterparties may remain in the narration; parties with outstanding balances can be represented by receivable or payable accounts.

For the current MVP, all postings in a transaction must use the same commodity and total debits must exactly equal total credits.

## Natural balances

Balance reports use each account type's natural sign:

| Account type | Increase |
|---|---|
| Asset | Debit |
| Expense | Debit |
| Liability | Credit |
| Equity | Credit |
| Income | Credit |

This makes ordinary balances display positively while preserving negative balances when an account moves against its normal direction.
