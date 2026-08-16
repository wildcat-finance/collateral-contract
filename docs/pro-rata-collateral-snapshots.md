# Pro-rata collateral release snapshots

This note sketches a prototype for physical-style collateral release after a Wildcat market default
or settlement trigger. Instead of forcing collateral through an AMM, a distributor releases the
collateral asset itself to debt holders by their agreed share of the debt at a snapshot point.

The prototype is intentionally narrow:

- it does not change Wildcat market-token ERC-20 behaviour;
- it does not claim onchain access to historical balances;
- it does not build a liquidation router; and
- it treats the reconciled snapshot as an authenticated input with a delay, not as magic.

The full study is in [pro-rata-collateral-study.md](fiat/pro-rata-collateral-study.md). The delivery
runbook is in [pro-rata-collateral-runbook.md](fiat/pro-rata-collateral-runbook.md).

## Why this exists

A BTC-backed USDC facility could want a default path where remaining BTC collateral is handed to
debt holders pro rata. That avoids forced sale pressure and lets the credit document say, roughly:
if the facility cannot be made good in USDC, the collateral is divided among the debt holders who
owned the claim at the chosen point.

That sounds simple until transfers, withdrawals and interest-bearing balances enter the picture.
Wildcat market tokens expose user-facing balances through a scale factor, while the durable claim
unit is the scaled balance. A clean release rule therefore needs a fixed snapshot of scaled debt,
or an explicit decision to use another unit.

## Chosen v0

The first prototype is an attested Merkle snapshot distributor.

1. A reconciler reconstructs debt-holder proportions for a market and snapshot point.
2. A snapshot authority proposes a Merkle root, total scaled debt and evidence hash.
3. The proposal waits through a review delay.
4. The root is finalised.
5. Each account claims collateral once with a Merkle proof.

This is not trustless. The point of v0 is to make the trust boundary small and visible. A later
version can replace the reconciler with a stronger ratifier set, a tracker hook deployed from market
inception, or a proof system.

## Why not mutate the debt token

Changing the market token to checkpoint every holder would put a specialised settlement feature in
the middle of a standard ERC-20 surface. It would also make every transfer pay for a product that
only some markets need. The prototype keeps the debt token plain and puts the extra accounting in a
separate contract.

## Why not use only ERC-20 events

ERC-20 `Transfer` events are not enough for an interest-bearing Wildcat claim. They report normalised
amounts, while proportional settlement is cleaner in scaled debt. Wildcat hooks can see scaled
amounts during deposits, transfers and queued withdrawals, so a future tracker hook can improve the
data trail without changing ERC-20 behaviour.

## What the audit should stare at

- bad roots redirecting collateral;
- the gap between historical truth and onchain verification;
- active balances versus unpaid withdrawal claims;
- scaled debt versus normalised debt;
- double claims;
- rounding dust;
- admin cancellation and finalisation timing; and
- collateral rescue after commitment.

The design is promising only if those risks stay explicit. If the product copy starts saying “the
contract knows all historical holders”, it has gone off the rails.
