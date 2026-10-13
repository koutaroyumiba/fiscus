# Personal Notes

There's a bunch of things that I'm learning while working on this project so I want a place to document all the learnings all in one place.

## Standard Conventions

Because I want this to be pretty robust and usable based on my high standard (self glaze), I'm learning about and following a lot of conventions that I kind of knew before but didn't really like understand/read in depth about.

ISO 3166 - standardised country codes
ISO 4217 - standardised currency codes
ISO 8601 - standardised date and time

## Random stuff

file extraction is kinda hard - a lot of design stuff to consider

one thing that I chose to do is to have the meta headers in each file (instead of having fragments which was suggested by AI...). This enables me to use the current logic (no need to define an extra 'fragment' or 'partial' document) and will allow for incremental migration when there is actually a new version.

---

A stable ID identifies a financial event independently of its display order. It's also useful because it acts as idempotency keys. The only problem with this is that it does make it more difficult on manual entry.

I feel like that's a big thing that I'm like balancing throughout this project - whether or not to lean towards like I guess the best way of doing things while ensuring that manual entry is still as simple and as easy as possible.

That's kind of how I came up with the current syntax of transaction - with a big decision being making the transaction id field optional (actually a lot of the fields in there are optional). I do agree that we only allow linking of transactions via explicit ids.

---

Some invariants for fiscus:
- Account and transaction IDs are nonempty and unique.
- Account names are unique under a documented comparison rule.
- Every posting references an existing account.
- Posting amounts are positive and exactly representable at the journal scale.
- Every transaction has at least two postings and at least one debit and credit.
- Total debits equal total credits without overflow.
- Dates are valid calendar dates.
- Correction links resolve and do not form invalid relationships.
- A failed validation or save leaves the existing journal unchanged.

Persistence and durability considerations:
- Validate the complete journal before replacing the current file.
- Write a temporary file on the same filesystem, flush as appropriate, and use
  atomic replacement where the platform supports it.
- Preserve a recoverable previous version.
- Reject overlapping writers.
- Document what is and is not guaranteed if the process, operating system, or
  storage device fails at each write stage.
- Test failures before writing, during writing, before replacement, and after
  replacement where practical.
- Never let a stored balance cache become an independent source of truth.


