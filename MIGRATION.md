# Migration UBIv1 -> UBIv2

The point is to migrate from the old v1 structure to the new structure, that's cheaper on gas terms.

We want:

1. this migration to be as seamless as possible.
2. this migration to be cheap to execute.

For 1, a way to do this is to attempt to execute this migration on transfer. If the migration hasn't been executed, then it is executed.

## Steps for the migration

1. Get the old balance, and write it on the new struct. Then, set the old balance to zero.
2. Do a PoH check. Depending on it, write "isHuman" or not.
3. If it was a human, get the old accrual, and figure out the accruedUbi. Add it to the new balance. Set this old accrual to zero. If it was not a human, just set the old accrual to zero.
4. Set the flag "hasMigrated" on the human.

It is not possible to have been the target of an UBI stream, because when someone attempts to give you an UBI stream, you update and attempt to do this migration I described. So there's no need to worry about that.

## How to make this migration seamless

Try to trigger this migration:

1. on transfer
2. on transferFrom
3. on being sent UBI

I didn't want to deal with the old structure, so I started from scratch.

But, the best course of action is to apply these techniques so that they're compatible with the proxy.
