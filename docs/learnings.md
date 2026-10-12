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
