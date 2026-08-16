# Audit log

## Step 1, round 1 -- 2026-08-16

| id | severity | file | finding | status |
| --- | --- | --- | --- | --- |
| none | none | docs / README | Docs-only step reviewed against the pro-rata collateral snapshot risk register; no Solidity changed and no security finding was identified. | closed |

Leads not pursued: Fizz was not run because step 1 ships no Solidity. The x-ray enumeration script
ran, but its nSLOC helper attempted `grep -P`, which macOS grep does not support; source enumeration
completed and nSLOC was recomputed manually as 1,305. `forge test --summary` passed 35/35 after the
docs changes. `hexaemeron:imprimatur` scored the touched prose at 100/100.

## Step 2, round 1 -- 2026-08-17

| id | severity | file | finding | status |
| --- | --- | --- | --- | --- |
| PRD-01 | high | `src/ProRataCollateralDistributor.sol` | `finalizeSnapshot` froze `totalCollateral` from the current token balance. An unprivileged caller could finalise after the review delay while the distributor was unfunded or underfunded, causing later collateral to be excluded from claims and swept as dust after claims completed. | fixed |
| PRD-02 | medium | `src/ProRataCollateralDistributor.sol` | `finalizeSnapshot` was public, so a claimant could front-run an authority cancellation at the review deadline and permanently finalise a bad pending root. | fixed |

Fixes:

- `SnapshotProposal` now commits to `collateralAmount`.
- `proposeSnapshot` rejects a zero collateral amount.
- `finalizeSnapshot` is authority-only.
- `finalizeSnapshot` requires the distributor balance to cover the proposed collateral amount before finalisation.
- `totalCollateral` is frozen from the proposed collateral amount, not from whatever balance happens to be present.

Verification after fixes:

- `forge test --match-contract ProRataCollateralDistributorTest --summary`: 9 passed, 0 failed.
- `forge test --summary`: 44 passed, 0 failed, 0 skipped.
- `git diff --check`: clean.
- Math, access and state-flow re-checks reported no remaining concrete findings. Residual leads are
  authority/evidence-process risks: the root total must match the leaf sum, leaves are portable if an
  authority reuses a root in the wrong domain, and non-standard collateral tokens can still create
  operational accounting surprises.
