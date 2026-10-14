# Fiscus Cookbook

Here are just some common situations that I run into in my day-to-day life and how I would go about representing it in `.fiscus`.

## Repo Structure

Recommended to structure your repo/folder like this:

```
JOURNAL-NAME/
    journal.fiscus      # main journal file
    accounts.fiscus     # main account file
    transactions/
        # up to you how you structure this
        2026/
            01.fiscus   # for january transactions
            ...
```

If following the above structure, in your `journal.fiscus`:

```fiscus
meta version 1
meta journal "JOURNAL-NAME"

source accounts "accounts.fiscus"
source transactions "transactions"
```

## Account Setup

Apart from the first component, you are free to define your account structure. Here's a sample account system for personal financial tracking:

```fiscus
# Equity
equity:opening-balances         # where your financial journey starts

# Assets
asset:bank:COUNTRY:INSTITUTION:ACCOUNT:SUBACCOUNT
asset:investment:COUNTRY:BROKER:ACCOUNT
asset:cash:CURRENCY

# stuff people owe to you
asset:receivables:PARTY

# Liabilities
liability:credit-card:NAME
liability:loan

# stuff you owe to people
liability:payables

# Income
income:COUNTRY:employment:EMPLOYER:[bonus, salary, interest]

# Expense
#   These should be the categories that you want to track.
#   Start broad, you can always extend the subcategories freely.
#   You can grow this list over time, just pick a good convention and stick to it.
expense:housing:rent
expense:food:groceries:[...]
expense:transport:[...]
expense:shopping:[...]
expense:leisure:[...]
expense:travel:[...]
```

## Normal Transaction:

```fiscus
txn YYYY-MM-DD {
    + expense:food:groceries 20 NZD
    - asset:bank 20 NZD
}
```

## Paying for someone:

```fiscus
# when you pay for them
txn YYYY-MM-DD {
    + asset:receivables:PARTY 5.5 NZD
    - asset:bank 5.5 NZD
}

# when they pay you back
txn YYYY-MM-DD {
    + asset:bank 5.5 NZD
    - asset:receivables:PARTY 5.5 NZD
}
```

## Reimbursing (paying someone back)

```fiscus
# when they pay for you
txn YYYY-MM-DD {
    + expense:food:coffee 6 NZD
    - liability:payables:PARTY 6 NZD
}

# when you pay them back
txn YYYY-MM-DD {
    + liability:payables:PARTY 6 NZD
    - asset:bank 6 NZD
}
```
