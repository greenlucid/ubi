# UBI

My own implementation of UBI.

## Features

- down to 40k gas on transfer (down from 64k gas, 37.5% cheaper)
- there are "streams" **sUBI** (don't confuse with DemocracyEarth's streams), an ERC-20 compatible (kinda) token that represent ongoing accruals of UBI.
  - they should just be used to display amounts.
  - i could make them compatible with `transfer` as well.
  - all its state really lives in UBI, to save gas.
- totalSupply is always precise, both for UBI and sUBI.
- made a proof of concept migrator contract.

# Disadvantages

- haven't made it work with proxy. Should not be too hard.
- requires a migration from the old structure, and it will cost a minimum of 10k gas per human.
