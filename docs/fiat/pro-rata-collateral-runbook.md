# Runbook: pro-rata collateral release snapshots

## Step 1: Commit the spec and user-facing framing

**Goal.** Commit the completed Fiat study and runbook so reviewers can judge the idea before
reading prototype code.

**Entry.** `main` at `d2f370963957eca2d5f72aa618e22ebf82ccddbe`, with `.hexaemeron/study.md`
receipted by the controller.

**Exit.** A committed docs page describes the problem, chosen design, non-goals and risk register
for attested pro-rata collateral release. The private `.hexaemeron/runbook.md` and
`.hexaemeron/study.md` are copied into tracked docs after the prose pass.

**Files.**

- `docs/pro-rata-collateral-snapshots.md`
- `docs/fiat/pro-rata-collateral-study.md`
- `docs/fiat/pro-rata-collateral-runbook.md`

**Tests.** Run `forge test --summary` to prove no code behaviour changed. Run the prose lint on the
new docs.

## Step 2: Add the attested collateral distributor

**Goal.** Add a minimal `ProRataCollateralDistributor` that can finalise an authenticated debt
snapshot and distribute collateral by Merkle-proven scaled-debt proportions.

**Entry.** Step 1 branch after its PR commit.

**Exit.** The distributor supports one collateral asset and one market per instance; a snapshot
authority can propose a root with `market`, `snapshotBlock`, `totalScaledDebt`,
`collateralAmount`, `merkleRoot`, `evidenceHash` and `reviewEndsAt`; the authority can cancel before
finalisation; the authority can finalise after the review delay once the distributor holds the
committed collateral amount; each account can claim once with a Merkle proof. Claimed amounts are
calculated as `floor(totalCollateral * scaledDebt / totalScaledDebt)`, and a deterministic dust path
prevents permanent accounting ambiguity.

**Files.**

- `src/ProRataCollateralDistributor.sol`
- `src/interfaces/IProRataCollateralDistributor.sol`
- `test/ProRataCollateralDistributor.t.sol`

**Tests.** Add unit tests for constructor validation, proposal, cancellation, finalisation delay,
bad proof rejection, double-claim rejection, pro-rata claims, dust handling and zero-total-debt
rejection. Run `forge test --summary`.

## Step 3: Add observability hooks and the end-to-end demo

**Goal.** Show how a reconciler gets the data it needs without changing the Wildcat market token.

**Entry.** Step 2 branch after its PR commit.

**Exit.** Add a small recorder/mock hook surface that emits scaled debt movements for deposits,
transfers and queued withdrawals, plus an end-to-end test that reconstructs a simple snapshot from
known balances, finalises the distributor and releases collateral to multiple debt holders. The demo
must show the lag explicitly: event trail, proposed root, review delay, finalisation, claims.

**Files.**

- `src/DebtSnapshotEventRecorder.sol`
- `src/interfaces/IDebtSnapshotEventRecorder.sol`
- `test/DebtSnapshotEventRecorder.t.sol`
- `test/ProRataCollateralReleaseDemo.t.sol`
- `docs/pro-rata-collateral-snapshots.md`

**Tests.** Add tests for emitted scaled movement events and the full demo path. Run
`forge test --summary`.
