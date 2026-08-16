# Wildcat market collateral contracts

Smart contracts for holding collateral against Wildcat credit markets and liquidating it when a
market enters penalised delinquency.

## What is here

- `WildcatMarketCollateralFactory` deploys collateral contracts with deterministic addresses.
- `SimpleMarketCollateral` supports borrower-owned collateral for one market.
- `SimpleMarketCollateralMultiParty` supports collateral deposits from many accounts and tracks each
  depositor's share of later liquidations.
- `ProRataCollateralDistributor` releases one collateral asset to debt holders from an attested
  Merkle snapshot.
- `DebtSnapshotEventRecorder` emits scaled-debt movement events for a reconciler to read; it does
  not settle claims or store balances.
- `docs/pro-rata-collateral-snapshots.md` sketches the pro-rata collateral release prototype being
  explored in issue [#5](https://github.com/wildcat-finance/collateral-contract/issues/5).

## Multi-party collateral

`SimpleMarketCollateralMultiParty` lets many users deposit one collateral asset for a Wildcat market.
Approved liquidators can sell collateral through Bebop PMM when the market is in penalised
delinquency, then send the received underlying asset to the market as repayment.

The contract tracks deposits with shares and tracks liquidation debits with a points-style accounting
system. A depositor who enters after a liquidation is not charged for that earlier liquidation. When
the market is closed, each depositor can reclaim its remaining collateral.

The current implementation does not support rebasing tokens or assets with non-standard transfer
semantics because it uses internal accounting rather than treating `balanceOf(address(this))` as the
source of truth. Tokens sent by mistake can be rescued by the borrower when the rescue does not
touch committed collateral.

## Pro-rata collateral snapshots

`ProRataCollateralDistributor` is a research prototype for physical-style settlement. A snapshot
authority proposes a Merkle root for one market, one collateral amount and one set of scaled debt
holders. After a review delay, the authority can finalise only when the distributor holds the
committed collateral amount. Holders then claim with Merkle proofs.

`DebtSnapshotEventRecorder` is the matching observability stub. A configured recorder address emits
deposit, transfer and queued-withdrawal movements in scaled debt units. The recorder is evidence for
an offchain reconciliation process, not the source of settlement truth.

## Factory

`WildcatMarketCollateralFactory` deploys collateral contracts with CREATE2. The deployment salt is
based on the collateral token and the associated market, so a market can have one collateral contract
per collateral asset. During deployment, the factory stores the borrower, collateral token and market
in transient storage for the collateral contract constructor.

The factory also lets the Wildcat arch-controller owner approve and remove liquidators.

## Known risks

- Liquidation depends on calldata supplied to Bebop PMM by an approved executor. A malicious executor
  and maker could sell collateral at a poor price.
- Cooldowns and maximum repayment checks limit liquidation cadence and over-repayment, but they do
  not make the swap price fair.
- Multi-party accounting rounds liquidation points up so the contract does not become insolvent. A
  depositor can be debited a few wei more than its exact proportional share.
- The pro-rata snapshot prototype trusts the configured snapshot authority and reconciler. A bad
  root can still encode a bad settlement.
- The repo contains a commented historical `WildcatMarketCollateral.sol`; current tests target
  `SimpleMarketCollateralMultiParty`, `ProRataCollateralDistributor` and
  `DebtSnapshotEventRecorder`.

## Development

This project uses Foundry.

```shell
git clone --recursive https://github.com/wildcat-finance/collateral-contract.git
cd collateral-contract
forge test
```

Coverage:

```shell
yarn coverage
```

## Licence

Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
