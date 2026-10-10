# Core Documentation

> Will make all of this nicer, this is just acting as a dump for now...

Currencies and securities are both commodities.

We treat ISO 4217 currencies as protected, built-in commodities. A journal may use an ISO currency without declaring it:

```fiscus
commodity AAPL security scale 6 quote USD
commodity BTC custom scale 8 quote USD
```

## Account structure

An account's type is inferred from the first component of its name. Accounts can
hold any commodity; a currency in an account name identifies a real-world
subaccount but does not constrain its postings.

```fiscus
asset:<category>[:<institution>[:<jurisdiction>[:<account>[:<subaccount>]]]]
liability:<category>[:<institution>[:<jurisdiction>[:<account>[:<subaccount>]]]]
income:<category>:<source>[:<detail>]
expense:<category>[:<subcategory>]
equity:<category>
```

Examples:

```fiscus
account asset:bank:commbank:au:everyday
account asset:bank:mufg:jp:ordinary

account asset:bank:wise:global:balance:aud
account asset:bank:wise:global:balance:eur
account asset:bank:wise:global:balance:jpy

# crypto
account asset:crypto:wallet:ledger:bitcoin
account asset:crypto:wallet:ledger:ethereum
account asset:crypto:exchange:kraken

account asset:cash:wallet:aud

account liability:credit-card:amex:au:platinum
account liability:credit-card:wise:global:card:aud
account liability:loan:commbank:au:home-loan
account liability:payable:friend

account income:employment:acme:salary
account income:employment:acme:bonus
account income:interest:wise
account income:dividends
account income:capital-gains:crypto

account expense:food:groceries
account expense:food:dining
account expense:housing:rent
account expense:housing:utilities
account expense:transport:public
account expense:financial:bank-fees
account expense:financial:trading-fees

account equity:opening-balances
account equity:contributions
account equity:withdrawals
```

## Conventions

1. Top-level names match the `AccountType` enum and determine the account type.
2. Account components are lowercase.
3. Country and currency identifiers use lowercase ISO codes.
4. Names describe stable identities rather than mutable properties.
5. Duplicate accounts use a short, non-sensitive suffix.
6. Closed account names are not reused.
7. Avoid relative labels such as `main` where possible.
8. Accounts accept any commodity by default.
9. Include currency in a name only when it distinguishes a real subaccount.
