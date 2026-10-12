# Fiscus Core Model

Fiscus uses double-entry accounting with exact, commodity-aware amounts.

## Commodities and amounts

An amount is a scaled integer paired with an internal commodity ID. Floating-point arithmetic is not used.

The current built-in commodities are AUD, NZD, and USD, each with scale 2. A journal may contain multiple currencies, and an account may hold a separate balance in each currency. Every individual transaction must currently balance in one currency.

Custom commodities, securities, price annotations, and currency conversion are planned but are not implemented.

## Workspaces and sources

A journal may be stored in one file or composed from typed sources:

```fiscus
meta version 1
meta journal "personal"

source accounts "accounts.fiscus"
source transactions "transactions"
```

Every source is a complete versioned `.fiscus` document with matching journal metadata. Account sources define the chart of accounts; transaction sources contain financial events. Directories are discovered recursively and loaded deterministically.

All account declarations are decoded before transactions, regardless of source order. This preserves global account validation while allowing transaction history to be split into manageable files.

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
