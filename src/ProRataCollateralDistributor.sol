// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import {MerkleProof} from "openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {IProRataCollateralDistributor} from "./interfaces/IProRataCollateralDistributor.sol";
import {LibERC20} from "./libraries/LibERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract ProRataCollateralDistributor is IProRataCollateralDistributor, ReentrancyGuard {
    using LibERC20 for address;

    address public immutable collateralAsset;
    address public immutable market;
    address public immutable snapshotAuthority;
    address public immutable dustRecipient;
    uint256 public immutable reviewDelay;

    SnapshotProposal public pendingSnapshot;

    bool public finalized;
    bool public dustSwept;

    uint256 public snapshotBlock;
    uint256 public totalScaledDebt;
    uint256 public totalCollateral;
    uint256 public totalClaimedScaledDebt;
    uint256 public totalClaimedCollateral;

    bytes32 public merkleRoot;
    bytes32 public evidenceHash;

    mapping(address account => bool claimed) public claimed;

    modifier onlySnapshotAuthority() {
        if (msg.sender != snapshotAuthority) {
            revert CallerNotSnapshotAuthority();
        }
        _;
    }

    constructor(
        address collateralAsset_,
        address market_,
        address snapshotAuthority_,
        address dustRecipient_,
        uint256 reviewDelay_
    ) {
        if (collateralAsset_ == address(0)) revert InvalidCollateralAsset();
        if (market_ == address(0)) revert InvalidMarket();
        if (snapshotAuthority_ == address(0)) {
            revert InvalidSnapshotAuthority();
        }
        if (dustRecipient_ == address(0)) revert InvalidDustRecipient();
        if (reviewDelay_ == 0) revert InvalidReviewDelay();

        collateralAsset = collateralAsset_;
        market = market_;
        snapshotAuthority = snapshotAuthority_;
        dustRecipient = dustRecipient_;
        reviewDelay = reviewDelay_;
    }

    function proposeSnapshot(
        address market_,
        uint256 snapshotBlock_,
        uint256 totalScaledDebt_,
        uint256 collateralAmount_,
        bytes32 merkleRoot_,
        bytes32 evidenceHash_,
        uint256 reviewEndsAt_
    ) external onlySnapshotAuthority {
        if (finalized) revert SnapshotAlreadyFinalized();
        if (pendingSnapshot.merkleRoot != bytes32(0)) {
            revert SnapshotProposalActive();
        }
        if (market_ != market) revert InvalidMarket();
        if (snapshotBlock_ == 0) revert InvalidSnapshotBlock();
        if (totalScaledDebt_ == 0) revert InvalidTotalScaledDebt();
        if (collateralAmount_ == 0) revert InvalidCollateralAmount();
        if (merkleRoot_ == bytes32(0)) revert InvalidMerkleRoot();
        if (evidenceHash_ == bytes32(0)) revert InvalidEvidenceHash();
        if (reviewEndsAt_ < block.timestamp + reviewDelay) {
            revert InvalidReviewEnd();
        }

        pendingSnapshot = SnapshotProposal({
            market: market_,
            snapshotBlock: snapshotBlock_,
            totalScaledDebt: totalScaledDebt_,
            collateralAmount: collateralAmount_,
            merkleRoot: merkleRoot_,
            evidenceHash: evidenceHash_,
            reviewEndsAt: reviewEndsAt_
        });

        emit SnapshotProposed(
            market_, snapshotBlock_, totalScaledDebt_, collateralAmount_, merkleRoot_, evidenceHash_, reviewEndsAt_
        );
    }

    function cancelSnapshot() external onlySnapshotAuthority {
        SnapshotProposal memory proposal = pendingSnapshot;
        if (proposal.merkleRoot == bytes32(0)) revert NoSnapshotProposal();

        delete pendingSnapshot;

        emit SnapshotCancelled(proposal.evidenceHash);
    }

    function finalizeSnapshot() external onlySnapshotAuthority {
        if (finalized) revert SnapshotAlreadyFinalized();

        SnapshotProposal memory proposal = pendingSnapshot;
        if (proposal.merkleRoot == bytes32(0)) revert NoSnapshotProposal();
        if (block.timestamp < proposal.reviewEndsAt) {
            revert ReviewPeriodActive();
        }

        uint256 balance = collateralAsset.balanceOf(address(this));
        if (balance < proposal.collateralAmount) {
            revert InsufficientCollateral();
        }

        finalized = true;
        snapshotBlock = proposal.snapshotBlock;
        totalScaledDebt = proposal.totalScaledDebt;
        merkleRoot = proposal.merkleRoot;
        evidenceHash = proposal.evidenceHash;
        totalCollateral = proposal.collateralAmount;

        delete pendingSnapshot;

        emit SnapshotFinalized(market, snapshotBlock, totalScaledDebt, totalCollateral, merkleRoot, evidenceHash);
    }

    function claim(uint256 scaledDebt, bytes32[] calldata proof, address recipient)
        external
        nonReentrant
        returns (uint256 collateralAmount)
    {
        if (!finalized) revert SnapshotNotFinalized();
        if (recipient == address(0)) revert InvalidRecipient();
        if (claimed[msg.sender]) revert AlreadyClaimed();

        bytes32 leaf = _leafHash(msg.sender, scaledDebt);
        if (!MerkleProof.verifyCalldata(proof, merkleRoot, leaf)) {
            revert InvalidProof();
        }

        claimed[msg.sender] = true;
        totalClaimedScaledDebt += scaledDebt;
        collateralAmount = FixedPointMathLib.fullMulDiv(totalCollateral, scaledDebt, totalScaledDebt);
        totalClaimedCollateral += collateralAmount;

        collateralAsset.safeTransfer(recipient, collateralAmount);

        emit Claimed(msg.sender, recipient, scaledDebt, collateralAmount);
    }

    function sweepDust() external nonReentrant returns (uint256 amount) {
        if (!finalized) revert SnapshotNotFinalized();
        if (dustSwept) revert DustAlreadySwept();
        if (totalClaimedScaledDebt != totalScaledDebt) {
            revert ClaimsIncomplete();
        }

        dustSwept = true;
        amount = collateralAsset.balanceOf(address(this));

        if (amount != 0) {
            collateralAsset.safeTransfer(dustRecipient, amount);
        }

        emit DustSwept(dustRecipient, amount);
    }

    function leafHash(address account, uint256 scaledDebt) external pure returns (bytes32) {
        return _leafHash(account, scaledDebt);
    }

    function _leafHash(address account, uint256 scaledDebt) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(account, scaledDebt))));
    }
}
