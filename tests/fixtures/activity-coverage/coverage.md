# Activity Coverage

This fixture records realistic personal activity using the current Fiscus language. Unsupported activities are documented rather than represented with lossy accounting entries.

## Fully representable

| Activity | Example |
|---|---|
| Opening bank balance | `opening-bank-nzd` |
| Opening foreign-currency balance | `opening-bank-aud` |
| Opening liability | `opening-credit-card`, `opening-loan` |
| Salary received net | `salary-2026-01` |
| Interest income | `interest-2026-01` |
| Cash dividend | `dividend-2026-01` |
| Purchase | `groceries-2026-01-11` |
| Split purchase | `split-purchase-2026-01-12` |
| Refund | `refund-2026-01-13` |
| Cash withdrawal | `cash-withdrawal-2026-01-14` |
| Cash spending | `transport-2026-01-16` |
| Same-currency transfer | `transfer-savings-2026-01` |
| Bank fee | `bank-fee-2026-01` |
| Gift or donation | `gift-2026-01-21` |
| Tax payment | `tax-2026-01-22` |
| Credit-card purchase | `card-groceries-2026-01-23` |
| Credit-card repayment | `card-payment-2026-01` |
| Loan principal and interest | `loan-payment-2026-01` |
| Shared expense | `shared-groceries-2026-01` |
| Reimbursement | `shared-reimbursement-2026-01` |

## Partially representable

| Activity | Preserved | Missing |
|---|---|---|
| Salary | Net cash and income | Gross pay, withholding and retirement deductions |
| Cash dividend | Cash and dividend income | Related security holding |
| Refund | Accounting reversal, note and tag | Explicit link to original purchase |
| Reimbursement | Receivable settlement, note and tags | Explicit link to original expense |

## Not faithfully representable

| Activity | Missing capability |
|---|---|
| NZD-to-AUD conversion | Multi-commodity valuation |
| Foreign-currency card purchase | Original and settlement currency relationship |
| Stock purchase | Cash-to-security valuation and acquisition cost |
| Stock sale | Security-to-cash valuation, proceeds and cost-basis data |
| Non-cash stock dividend | Valuation and income-recognition rules |
| Market valuation | Price declarations |
| Employee shares or options | Security and option model |
| Statement balance assertion | Assertion syntax |

## Expected totals

The workspace contains:

- 18 accounts
- 23 transactions

Selected final natural balances:

| Account | Balance |
|---|---:|
| `asset:bank:nzd:everyday` | `6390.00 NZD` |
| `asset:bank:nzd:savings` | `2500.00 NZD` |
| `asset:bank:aud:everyday` | `1000.00 AUD` |
| `asset:cash:nzd` | `170.00 NZD` |
| `asset:receivable:shared` | `0.00 NZD` |
| `liability:credit-card:nzd` | `250.00 NZD` |
| `liability:loan:nzd` | `9600.00 NZD` |
| `income:salary` | `3000.00 NZD` |
| `income:interest` | `10.00 NZD` |
| `income:dividend` | `40.00 NZD` |
| `expense:food:groceries` | `315.00 NZD` |
| `expense:household` | `40.00 NZD` |
| `expense:transport` | `30.00 NZD` |
| `expense:bank-fees` | `5.00 NZD` |
| `expense:gifts` | `50.00 NZD` |
| `expense:tax` | `200.00 NZD` |
| `expense:loan-interest` | `50.00 NZD` |

## Current recording policy

- Begin from a fresh start date.
- Record opening balances against `equity:opening-balances`.
- Record transactions after they clear.
- Give every transaction a stable ID.
- Use notes for additional human-readable context.
- Use tags for classifications that cut across the account hierarchy.
- Do not approximate currency conversions or investment activity using incomplete entries.
