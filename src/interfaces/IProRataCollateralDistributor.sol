// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

interface IProRataCollateralDistributor {
    struct SnapshotProposal {
        address market;
        uint256 snapshotBlock;
        uint256 totalScaledDebt;
        bytes32 merkleRoot;
        bytes32 evidenceHash;
        uint256 reviewEndsAt;
    }

    event SnapshotProposed(
        address indexed market,
        uint256 indexed snapshotBlock,
        uint256 totalScaledDebt,
        bytes32 merkleRoot,
        bytes32 evidenceHash,
        uint256 reviewEndsAt
    );

    event SnapshotCancelled(bytes32 indexed evidenceHash);

    event SnapshotFinalized(
        address indexed market,
        uint256 indexed snapshotBlock,
        uint256 totalScaledDebt,
        uint256 totalCollateral,
        bytes32 merkleRoot,
        bytes32 evidenceHash
    );

    event Claimed(address indexed account, address indexed recipient, uint256 scaledDebt, uint256 collateralAmount);

    event DustSwept(address indexed recipient, uint256 amount);

    error CallerNotSnapshotAuthority();
    error InvalidCollateralAsset();
    error InvalidMarket();
    error InvalidSnapshotAuthority();
    error InvalidDustRecipient();
    error InvalidReviewDelay();
    error InvalidSnapshotBlock();
    error InvalidTotalScaledDebt();
    error InvalidMerkleRoot();
    error InvalidEvidenceHash();
    error InvalidReviewEnd();
    error SnapshotAlreadyFinalized();
    error SnapshotNotFinalized();
    error SnapshotProposalActive();
    error NoSnapshotProposal();
    error ReviewPeriodActive();
    error InvalidProof();
    error AlreadyClaimed();
    error InvalidRecipient();
    error ClaimsIncomplete();
    error DustAlreadySwept();

    function proposeSnapshot(
        address market,
        uint256 snapshotBlock,
        uint256 totalScaledDebt,
        bytes32 merkleRoot,
        bytes32 evidenceHash,
        uint256 reviewEndsAt
    ) external;

    function cancelSnapshot() external;

    function finalizeSnapshot() external;

    function claim(uint256 scaledDebt, bytes32[] calldata proof, address recipient)
        external
        returns (uint256 collateralAmount);

    function sweepDust() external returns (uint256 amount);

    function leafHash(address account, uint256 scaledDebt) external pure returns (bytes32);
}
