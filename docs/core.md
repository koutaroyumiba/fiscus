# Core Documentation

> Will make all of this nicer, this is just acting as a dump for now...

Currencies and securities are both commodities.

We treat ISO 4217 currencies as protected, built-in commodities. A journal may use an ISO currency without declaring it:

```fiscus
commodity AAPL security scale 6 quote USD
commodity BTC custom scale 8 quote USD
```

