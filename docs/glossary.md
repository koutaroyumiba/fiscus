# Fiscus Accounting Glossary

> this is AI generated... will remake later but I lwk don't know the terms too...

Fiscus is based on **double-entry accounting**. Every financial event is recorded as a transaction containing two or more postings.

## Core Structure

### Journal

A **journal** is the complete chronological collection of accounts and transactions.

```fis
journal "personal" {
    ...
}
```

It is roughly equivalent to an accounting book or ledger file.

### Account

An **account** is a named bucket used to classify value.

```fis
account assets:bank        asset
account expenses:groceries expense
```

Account names are hierarchical:

- `assets`
- `assets:bank`
- `assets:brokerage:cash`

The colon-separated components allow related accounts to be grouped and summarized.

A complete list of accounts is often called the **chart of accounts**.

### Transaction

A **transaction** records one financial event.

```fis
transaction groceries-001 2026-01-17 "Groceries" {
    debit  expenses:groceries 82.40 AUD
    credit assets:bank        82.40 AUD
}
```

It contains:

- a unique identifier: `groceries-001`
- a date: `2026-01-17`
- a description: `"Groceries"`
- two or more postings

The whole transaction must balance.

### Posting

A **posting** is one line inside a transaction. It records a change to one account.

```fis
debit expenses:groceries 82.40 AUD
```

This posting has:

- a direction: debit
- an account: `expenses:groceries`
- an amount: `82.40`
- a commodity: `AUD`

A useful distinction is:

- **Transaction:** the entire event
- **Posting:** one account's side of that event

For example, buying groceries is one transaction with two postings:

1. Grocery expense increases.
2. Bank balance decreases.

## Double-Entry Accounting

Every transaction affects at least two accounts, and total debits must equal total credits.

```fis
debit  expenses:groceries 82.40 AUD
credit assets:bank        82.40 AUD
```

This does **not** mean money was duplicated. It records both sides of the same event:

- what was received or incurred
- where its value came from

An **unbalanced transaction** is invalid:

```fis
debit  expenses:groceries 20.00 AUD
credit assets:bank        19.00 AUD
```

## Debit and Credit

**Debit** and **credit** are accounting directions, not synonyms for "bad" and "good," or simply "money in" and "money out."

| Account type | Increases with | Decreases with |
|---|---|---|
| Asset | Debit | Credit |
| Expense | Debit | Credit |
| Liability | Credit | Debit |
| Equity | Credit | Debit |
| Income | Credit | Debit |

For example:

```fis
debit  assets:bank   3000.00 AUD
credit income:salary 3000.00 AUD
```

- The bank asset increases with a debit.
- Salary income increases with a credit.

The side that normally increases an account is called its **normal balance**.

## The Five Account Types

### Asset

Something you own or control that has value.

Examples:

- bank account
- cash
- shares
- money owed to you
- property

```fis
account assets:bank asset
```

Assets increase with debits and decrease with credits.

### Liability

Something you owe.

Examples:

- credit card debt
- mortgage
- unpaid bills
- loans

```fis
account liabilities:credit-card liability
```

Liabilities increase with credits and decrease with debits.

A credit-card purchase might be:

```fis
debit  expenses:groceries       82.40 AUD
credit liabilities:credit-card 82.40 AUD
```

### Equity

The residual value after subtracting liabilities from assets.

```text
assets - liabilities = equity
```

Examples include:

- owner contributions
- retained value
- opening balances

```fis
account equity:opening-balances equity
```

An opening balance uses equity to explain where an existing asset balance came from:

```fis
debit  assets:bank             1000.00 AUD
credit equity:opening-balances 1000.00 AUD
```

### Income

Value earned or received.

Examples:

- salary
- interest
- dividends
- sales revenue

```fis
account income:salary income
```

Income increases with credits.

### Expense

Value consumed or spent.

Examples:

- groceries
- rent
- brokerage fees
- transport

```fis
account expenses:groceries expense
```

Expenses increase with debits.

## Accounting Equation

The fundamental accounting equation is:

```text
assets - liabilities = equity
```

Including activity over a period:

```text
assets - liabilities = equity + income - expenses
```

Double-entry accounting keeps this equation consistent.

## Balance

An account's **balance** is the net result of all postings made to it.

Given:

```fis
debit  assets:bank 1000.00 AUD
debit  assets:bank 3000.00 AUD
credit assets:bank   82.40 AUD
```

The bank balance is:

```text
1000.00 + 3000.00 - 82.40 = 3917.60 AUD
```

A **trial balance** summarizes all account balances and checks that total debits equal total credits.

## Commodity

A **commodity** is the thing being measured or transferred.

Currencies are commodities:

- `AUD`
- `NZD`
- `USD`

Securities can also be commodities:

- `AAPL`
- shares in a fund
- cryptocurrency

Thus an amount is not merely `100`; it is something like:

```text
100.00 AUD
10 AAPL
```

Amounts in different commodities cannot be directly added without a conversion price.

## Currency and Minor Units

A **currency code** identifies a currency, generally using ISO 4217 codes such as `AUD` and `NZD`.

Currencies also have a defined number of fractional digits. AUD uses two, so:

```text
10.00 AUD   valid
10.005 AUD  invalid
```

Internally, Fiscus's current `Money` type stores an integer amount and currency. Integer storage avoids floating-point rounding problems. For example, an eventual representation would typically treat `10.25 AUD` as 1,025 cents.

## Security

A **security** is a tradable financial instrument such as a share.

```fis
commodity AAPL security scale 6 quote USD
```

Here:

- `AAPL` is the commodity symbol.
- `security` classifies it as an investment instrument.
- `scale 6` allows quantities with up to six fractional digits.
- `quote USD` says its prices are normally expressed in USD.

## Scale

**Scale** is the maximum supported fractional precision of a commodity.

For example, scale 6 allows:

```text
1.123456 AAPL
```

This is useful for fractional shares or other precisely measured commodities.

## Quote Currency

The **quote currency** is the currency in which a commodity's price is expressed.

If AAPL is quoted in USD:

```text
180.00 USD per AAPL
```

USD is the quote currency.

## Price Annotation

The `@` notation gives a price or conversion rate:

```fis
debit assets:brokerage:aapl 10 AAPL @ 180.00 USD
```

This means:

```text
10 AAPL × 180.00 USD/AAPL = 1800.00 USD
```

Similarly:

```fis
debit assets:bank:nzd 108.25 NZD @ 0.92378753 AUD
```

means each NZD is valued at approximately `0.92378753 AUD`, making the posting worth about `100 AUD`.

The quantity and valuation commodity are different:

- quantity: `108.25 NZD`
- valuation: approximately `100 AUD`

## Opening Balance

An **opening balance** records value that existed before the journal began.

```fis
debit  assets:bank             1000.00 AUD
credit equity:opening-balances 1000.00 AUD
```

The equity posting prevents the initial asset from appearing without an accounting source.

## Ledger

A **ledger** organizes postings by account rather than by transaction.

The journal view asks:

> What events happened chronologically?

The ledger view asks:

> What happened to this particular account?

For example, the `assets:bank` ledger would contain every posting involving that account.

## Reports

Reports are derived from journal data:

- **Balance sheet:** assets, liabilities, and equity at a point in time
- **Income statement:** income and expenses over a period
- **Cash-flow report:** movement of cash over a period
- **Account ledger:** postings for a selected account
- **Trial balance:** debit and credit balances used to verify consistency

## Validation

Fiscus's examples indicate that a valid journal should enforce:

- valid calendar dates
- valid commodity precision
- declared accounts
- balanced transactions
- compatible currencies or explicit conversion prices
- unique transaction identifiers
- exact arithmetic without floating-point rounding

The DSL examples are currently exploratory—the journal, account, transaction, and posting syntax shown in `examples/` has not yet been implemented.
