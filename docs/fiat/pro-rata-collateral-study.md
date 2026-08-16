# Study: pro-rata collateral release snapshots

## Problem statement

Build a prototype for physical-style collateral release when a Wildcat market has many debt
holders and collateral should be divided by debt ownership at a chosen settlement point.

The user story is a BTC-backed USDC facility where, after a default or other agreed trigger, the
remaining BTC collateral can be released to debt holders pro rata instead of forcing an AMM sale.
The hard part is not the division formula. The hard part is recording who owned what share of the
Wildcat debt at the settlement point without changing the market token into a bespoke ERC-20.

For this run, “working prototype” means:

1. a small contract can accept an authenticated snapshot of debt-holder proportions for a market;
2. the snapshot can be finalised after a review delay;
3. collateral held by the distributor can be claimed once per account using those proportions; and
4. tests show that the full collateral pool is allocated by the committed proportions, with dust
   handled deterministically.

The prototype does not need to be fully trustless. It must make the trust boundary explicit enough
that a later design can replace the reconciler with a stronger attestation or proof system.

Tracking issue: <https://github.com/wildcat-finance/collateral-contract/issues/5>.

## Prior art

### In this repository

- `src/SimpleMarketCollateralMultiParty.sol` already implements the inverse accounting problem:
  several collateral depositors supply one collateral pool, liquidation debits are assigned by
  per-share points, and post-termination `reclaimCollateral()` returns each depositor's remaining
  collateral.
- `src/SimpleMarketCollateral.sol` is the borrower-only version. It sells collateral through Bebop
  and sends the underlying asset to the Wildcat market.
- `src/WildcatMarketCollateralFactory.sol` deploys `SimpleMarketCollateralMultiParty` with
  borrower, market and collateral parameters pulled from transient storage.
- `test/SimpleMarketCollateralMultiParty.t.sol` and
  `test/SimpleMarketCollateralMultiParty.invariant.t.sol` give the current unit and invariant
  style. Baseline command run during study: `forge test --summary`, 35 passed, 0 failed.

The existing multi-party collateral accounting is useful because it already treats “fairness” as a
points problem rather than an array of holders problem. The new feature runs in the other direction:
split collateral among debt holders, not among collateral providers.

### In `v2-protocol`

The submodule is pinned at `f5c39bcd224c558d18cb53568c785efac0db0835`.

- `lib/v2-protocol/src/market/WildcatMarketToken.sol` implements ERC-20 actions for market tokens.
  `balanceOf(account)` returns a normalised balance by applying the current `scaleFactor`, while
  `scaledBalanceOf(account)` returns the stored scaled claim.
- `WildcatMarketToken._transfer()` converts the requested normalised transfer amount into
  `scaledAmount`, calls the configured hook, then mutates sender and recipient scaled balances and
  emits a normal ERC-20 `Transfer` event with the requested normalised amount.
- `lib/v2-protocol/src/market/WildcatMarketBase.sol` exposes `scaledTotalSupply()` and
  `scaleFactor()`. The market also emits ERC-20 `Transfer` events when withdrawal batch payments
  burn debt.
- `lib/v2-protocol/src/access/IHooks.sol` and `lib/v2-protocol/src/types/HooksConfig.sol` show that
  a market can enable `onDeposit`, `onTransfer`, `onQueueWithdrawal`, `onExecuteWithdrawal`, and
  other callbacks, but a deployed market has one hooks configuration.

Those facts matter because ERC-20 `Transfer` events alone are not a complete proportional ledger for
an interest-bearing Wildcat claim. The scaled balance is the durable claim unit. A hook can see
`scaledAmount`, but only markets deployed with such a hook from inception can get an onchain transfer
trail without protocol changes.

### Standards and external references

- EIP-20 defines the standard token API and `Transfer` event. The prototype should avoid changing
  market-token transfer semantics or relying on non-standard token behaviour:
  <https://eips.ethereum.org/EIPS/eip-20>.
- EIP-4626 defines tokenised vault shares over one ERC-20 asset. A wrapper/vault design is relevant
  when a single controlled wrapper owns the Wildcat debt and users hold wrapper shares:
  <https://eips.ethereum.org/EIPS/eip-4626>.

## Constraints and non-goals

- Starting point: `wildcat-finance/collateral-contract` `main` at
  `d2f370963957eca2d5f72aa618e22ebf82ccddbe`.
- Toolchain: Foundry, Solidity `>=0.8.20`; compilation currently uses solc `0.8.28`.
- The repo is Apache-2.0 WITH LicenseRef-Commons-Clause-1.0.
- Do not merge automatically. The output must be branch and PR only.
- Do not mutate Wildcat market token ERC-20 behaviour.
- Do not assume onchain access to historical balances. The EVM cannot ask a contract what
  `scaledBalanceOf(account)` was at an old block unless that contract recorded the value.
- Do not build an AMM or liquidation router in this prototype.
- Do not solve BTC price observation, BRC option payoff, liquidation eligibility, sanctions escrow
  handling, or legal classification in this repo.
- Do not claim the snapshot source is trustless if it is an attested offchain reconciliation.

## Design options

### Option A: Merkle snapshot distributor with attested root

A `ProRataCollateralDistributor` holds collateral for one market. A snapshot authority proposes:

- market;
- collateral asset;
- snapshot block or settlement timestamp;
- total scaled debt in the snapshot;
- Merkle root of `(account, scaledDebt)` leaves; and
- evidence hash for the reconciliation bundle.

After a review delay, the root can be finalised. Each account claims collateral with a Merkle proof.
The claim amount is `floor(totalCollateral * scaledDebt / totalScaledDebt)`, with the last claim or
an explicit dust recipient handling remainder.

Trade: simplest useful prototype, no ERC-20 changes, works with existing markets if the authority
can reconstruct holders. The cost is trust in the authority or ratifier set. A challenge path can
pause or replace bad roots, but it cannot verify arbitrary historical balances onchain without more
machinery.

### Option B: live onchain scaled-balance tracker hook

A hooks template updates a mapping on `onDeposit`, `onTransfer` and `onQueueWithdrawal`, tracking
current scaled claims for every lender. Settlement freezes that mapping and a collateral distributor
uses it.

Trade: stronger data, weaker deployability. It only works for markets deployed with the tracker hook
from the start, costs gas on each transfer path, needs careful coverage of deposits, withdrawals,
force-buybacks, sanctions flows and market closure, and competes with existing hooks because a market
has one hooks configuration.

### Option C: ERC-4626-style fixed-supply wrapper

A wrapper or vault owns the Wildcat debt. Users hold wrapper shares, and physical settlement divides
collateral by wrapper shares at settlement.

Trade: clean for new structured products, poor for general markets. It solves holder enumeration by
making the wrapper the only market lender, but it changes the product shape and does not help an
ordinary multi-lender Wildcat market after the fact.

### Option D: mutate the debt token into a checkpointed token

Add checkpoints or per-block holder accounting to the Wildcat market token itself.

Trade: strongest direct source if done perfectly, but the wrong prototype. It expands protocol audit
surface, changes ERC-20 expectations, and forces all markets to pay for a feature only some
collateral products need.

## Picked design

Pick Option A first: an attested Merkle snapshot distributor.

It is the cheapest construction that proves whether the product idea is useful. It keeps Wildcat
market tokens standard, avoids AMM sale pressure, and makes the offline reconciliation lag explicit:
settlement can wait a few hours while an indexer and ratifiers produce the root. If the prototype is
useful, Option B can be added later as a stronger source for markets launched with a tracker hook.

The study reading of the user's idea is:

- use events and optional hooks to improve observability;
- use an offchain reconciler because historic holder sets are not enumerable onchain;
- commit the reconciled result onchain before collateral release; and
- accept a delay/challenge window as part of the physical-settlement product.

## Risk register seed

- **Snapshot authority.** A bad root can redirect collateral. The first prototype must name the
  proposer/admin role and provide at least a review delay and cancellation path.
- **Historical truth.** Onchain contracts cannot verify old `scaledBalanceOf` values for arbitrary
  accounts. Any claim of truth must come from a committed data bundle, multiple ratifiers, a tracker
  hook deployed from inception, or a proof system not built in step 1.
- **Scaled versus normalised debt.** Wildcat market tokens accrue through `scaleFactor`. Settlement
  proportions should use scaled debt unless the product deliberately wants time-of-snapshot
  normalised balances.
- **Withdrawal state.** Debt queued into withdrawal batches may no longer be an active market-token
  balance but may still be an unpaid claim. A real release rule must decide whether the snapshot
  includes active balances only, unpaid withdrawal claims, or both.
- **Dust and rounding.** `floor(totalCollateral * accountDebt / totalDebt)` leaves remainder. The
  contract needs deterministic dust handling and tests over small numbers.
- **Double claim.** Each leaf/account must be claimable once.
- **Collateral custody.** The distributor must not let borrower/admin rescue committed collateral
  after finalisation.
- **Reorg and lag.** A snapshot block should have enough confirmations before the root is proposed.
  The review delay is a product feature, not a bug.
- **Sanctions and blocked recipients.** This repo already interacts with Wildcat markets. A later
  production design must decide whether claim recipients can be blocked, escrowed or redirected.
- **Upgrade/admin risk.** Any mutable root or authority must be frozen once finalised.

## Glossary seeds

- **Snapshot block:** the block whose debt-holder proportions control collateral release.
- **Scaled debt:** Wildcat claim units before applying `scaleFactor`; durable for proportional
  accounting.
- **Normalised debt:** user-facing balance after applying `scaleFactor`; useful for display, not the
  first-choice settlement unit.
- **Reconciler:** offchain process that reconstructs holder proportions and prepares the snapshot
  bundle.
- **Snapshot authority:** onchain role allowed to propose or cancel roots.
- **Evidence hash:** digest of the reconciliation bundle, source ranges and tool outputs.
- **Review delay:** time between root proposal and finalisation.
- **Claim leaf:** encoded `(account, scaledDebt)` entry in the Merkle tree.
- **Dust:** collateral remainder caused by integer division.
- **Physical-style settlement:** distributing the collateral asset itself instead of selling it for
  the market's underlying asset.

## Sources

- `README.md`
- `foundry.toml`
- `package.json`
- `src/SimpleMarketCollateralMultiParty.sol`
- `src/SimpleMarketCollateral.sol`
- `src/WildcatMarketCollateralFactory.sol`
- `test/SimpleMarketCollateralMultiParty.t.sol`
- `test/SimpleMarketCollateralMultiParty.invariant.t.sol`
- `test/BaseTest.sol`
- `lib/v2-protocol/src/market/WildcatMarketToken.sol`
- `lib/v2-protocol/src/market/WildcatMarketBase.sol`
- `lib/v2-protocol/src/access/IHooks.sol`
- `lib/v2-protocol/src/types/HooksConfig.sol`
- EIP-20: <https://eips.ethereum.org/EIPS/eip-20>
- EIP-4626: <https://eips.ethereum.org/EIPS/eip-4626>
