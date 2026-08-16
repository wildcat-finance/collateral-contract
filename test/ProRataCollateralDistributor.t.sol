// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {ProRataCollateralDistributor} from "src/ProRataCollateralDistributor.sol";
import {IProRataCollateralDistributor} from "src/interfaces/IProRataCollateralDistributor.sol";

contract ProRataCollateralDistributorTest is Test {
    MockERC20 collateralAsset;
    ProRataCollateralDistributor distributor;

    address market = address(0x1234);
    address authority = address(0xA11CE);
    address dustRecipient = address(0xD057);
    address alice = address(0xA);
    address bob = address(0xB);
    address carol = address(0xC);
    uint256 reviewDelay = 1 days;

    function setUp() public {
        collateralAsset = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        distributor =
            new ProRataCollateralDistributor(address(collateralAsset), market, authority, dustRecipient, reviewDelay);
    }

    function testConstructorValidation() public {
        vm.expectRevert(IProRataCollateralDistributor.InvalidCollateralAsset.selector);
        new ProRataCollateralDistributor(address(0), market, authority, dustRecipient, reviewDelay);

        vm.expectRevert(IProRataCollateralDistributor.InvalidMarket.selector);
        new ProRataCollateralDistributor(address(collateralAsset), address(0), authority, dustRecipient, reviewDelay);

        vm.expectRevert(IProRataCollateralDistributor.InvalidSnapshotAuthority.selector);
        new ProRataCollateralDistributor(address(collateralAsset), market, address(0), dustRecipient, reviewDelay);

        vm.expectRevert(IProRataCollateralDistributor.InvalidDustRecipient.selector);
        new ProRataCollateralDistributor(address(collateralAsset), market, authority, address(0), reviewDelay);

        vm.expectRevert(IProRataCollateralDistributor.InvalidReviewDelay.selector);
        new ProRataCollateralDistributor(address(collateralAsset), market, authority, dustRecipient, 0);
    }

    function testProposalValidationAndStorage() public {
        bytes32 root = _leaf(alice, 1 ether);
        bytes32 evidence = keccak256("evidence");
        uint256 reviewEndsAt = block.timestamp + reviewDelay;

        vm.expectRevert(IProRataCollateralDistributor.CallerNotSnapshotAuthority.selector);
        distributor.proposeSnapshot(market, block.number, 1 ether, 10 ether, root, evidence, reviewEndsAt);

        vm.startPrank(authority);
        vm.expectRevert(IProRataCollateralDistributor.InvalidMarket.selector);
        distributor.proposeSnapshot(address(0xBEEF), block.number, 1 ether, 10 ether, root, evidence, reviewEndsAt);

        vm.expectRevert(IProRataCollateralDistributor.InvalidSnapshotBlock.selector);
        distributor.proposeSnapshot(market, 0, 1 ether, 10 ether, root, evidence, reviewEndsAt);

        vm.expectRevert(IProRataCollateralDistributor.InvalidTotalScaledDebt.selector);
        distributor.proposeSnapshot(market, block.number, 0, 10 ether, root, evidence, reviewEndsAt);

        vm.expectRevert(IProRataCollateralDistributor.InvalidCollateralAmount.selector);
        distributor.proposeSnapshot(market, block.number, 1 ether, 0, root, evidence, reviewEndsAt);

        vm.expectRevert(IProRataCollateralDistributor.InvalidMerkleRoot.selector);
        distributor.proposeSnapshot(market, block.number, 1 ether, 10 ether, bytes32(0), evidence, reviewEndsAt);

        vm.expectRevert(IProRataCollateralDistributor.InvalidEvidenceHash.selector);
        distributor.proposeSnapshot(market, block.number, 1 ether, 10 ether, root, bytes32(0), reviewEndsAt);

        vm.expectRevert(IProRataCollateralDistributor.InvalidReviewEnd.selector);
        distributor.proposeSnapshot(market, block.number, 1 ether, 10 ether, root, evidence, reviewEndsAt - 1);

        distributor.proposeSnapshot(market, block.number, 1 ether, 10 ether, root, evidence, reviewEndsAt);

        (
            address storedMarket,
            uint256 storedSnapshotBlock,
            uint256 storedTotalScaledDebt,
            uint256 storedCollateralAmount,
            bytes32 storedRoot,
            bytes32 storedEvidence,
            uint256 storedReviewEndsAt
        ) = distributor.pendingSnapshot();

        assertEq(storedMarket, market);
        assertEq(storedSnapshotBlock, block.number);
        assertEq(storedTotalScaledDebt, 1 ether);
        assertEq(storedCollateralAmount, 10 ether);
        assertEq(storedRoot, root);
        assertEq(storedEvidence, evidence);
        assertEq(storedReviewEndsAt, reviewEndsAt);

        vm.expectRevert(IProRataCollateralDistributor.SnapshotProposalActive.selector);
        distributor.proposeSnapshot(market, block.number, 1 ether, 10 ether, root, evidence, reviewEndsAt);
        vm.stopPrank();
    }

    function testCancelProposal() public {
        _propose(_leaf(alice, 1 ether), 1 ether, 1 ether);

        vm.prank(authority);
        distributor.cancelSnapshot();

        (,,,, bytes32 storedRoot,,) = distributor.pendingSnapshot();
        assertEq(storedRoot, bytes32(0));

        vm.prank(authority);
        vm.expectRevert(IProRataCollateralDistributor.NoSnapshotProposal.selector);
        distributor.cancelSnapshot();
    }

    function testFinalizeRequiresDelayAndCapturesCollateral() public {
        bytes32 root = _leaf(alice, 1 ether);
        _propose(root, 1 ether, 10 ether);
        collateralAsset.mint(address(distributor), 10 ether);

        vm.prank(authority);
        vm.expectRevert(IProRataCollateralDistributor.ReviewPeriodActive.selector);
        distributor.finalizeSnapshot();

        vm.warp(block.timestamp + reviewDelay);
        vm.expectRevert(IProRataCollateralDistributor.CallerNotSnapshotAuthority.selector);
        distributor.finalizeSnapshot();

        vm.prank(authority);
        distributor.finalizeSnapshot();

        assertTrue(distributor.finalized());
        assertEq(distributor.merkleRoot(), root);
        assertEq(distributor.totalScaledDebt(), 1 ether);
        assertEq(distributor.totalCollateral(), 10 ether);

        vm.prank(authority);
        vm.expectRevert(IProRataCollateralDistributor.SnapshotAlreadyFinalized.selector);
        distributor.finalizeSnapshot();
    }

    function testFinalizeRequiresExpectedCollateralBalance() public {
        _propose(_leaf(alice, 1 ether), 1 ether, 10 ether);
        collateralAsset.mint(address(distributor), 9 ether);
        vm.warp(block.timestamp + reviewDelay);

        vm.prank(authority);
        vm.expectRevert(IProRataCollateralDistributor.InsufficientCollateral.selector);
        distributor.finalizeSnapshot();

        collateralAsset.mint(address(distributor), 1 ether);

        vm.prank(authority);
        distributor.finalizeSnapshot();

        assertEq(distributor.totalCollateral(), 10 ether);
    }

    function testRejectsBadProof() public {
        bytes32 aliceLeaf = _leaf(alice, 1 ether);
        bytes32 bobLeaf = _leaf(bob, 1 ether);
        _propose(_root2(aliceLeaf, bobLeaf), 2 ether, 100 ether);
        collateralAsset.mint(address(distributor), 100 ether);
        vm.warp(block.timestamp + reviewDelay);
        vm.prank(authority);
        distributor.finalizeSnapshot();

        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = aliceLeaf;

        vm.prank(alice);
        vm.expectRevert(IProRataCollateralDistributor.InvalidProof.selector);
        distributor.claim(1 ether, badProof, alice);
    }

    function testClaimsProRataAndRejectsDoubleClaim() public {
        bytes32 aliceLeaf = _leaf(alice, 1 ether);
        bytes32 bobLeaf = _leaf(bob, 3 ether);
        _propose(_root2(aliceLeaf, bobLeaf), 4 ether, 1000 ether);
        collateralAsset.mint(address(distributor), 1000 ether);
        vm.warp(block.timestamp + reviewDelay);
        vm.prank(authority);
        distributor.finalizeSnapshot();

        bytes32[] memory aliceProof = new bytes32[](1);
        aliceProof[0] = bobLeaf;
        vm.prank(alice);
        uint256 aliceClaim = distributor.claim(1 ether, aliceProof, alice);
        assertEq(aliceClaim, 250 ether);
        assertEq(collateralAsset.balanceOf(alice), 250 ether);

        vm.prank(alice);
        vm.expectRevert(IProRataCollateralDistributor.AlreadyClaimed.selector);
        distributor.claim(1 ether, aliceProof, alice);

        bytes32[] memory bobProof = new bytes32[](1);
        bobProof[0] = aliceLeaf;
        vm.prank(bob);
        uint256 bobClaim = distributor.claim(3 ether, bobProof, bob);
        assertEq(bobClaim, 750 ether);
        assertEq(collateralAsset.balanceOf(bob), 750 ether);

        assertEq(distributor.totalClaimedScaledDebt(), 4 ether);
        assertEq(distributor.totalClaimedCollateral(), 1000 ether);
    }

    function testDustCanOnlyBeSweptAfterAllScaledDebtClaims() public {
        bytes32 aliceLeaf = _leaf(alice, 1);
        bytes32 bobLeaf = _leaf(bob, 1);
        bytes32 carolLeaf = _leaf(carol, 1);
        bytes32 pair = _hashPair(aliceLeaf, bobLeaf);

        _propose(_hashPair(pair, carolLeaf), 3, 100);
        collateralAsset.mint(address(distributor), 100);
        vm.warp(block.timestamp + reviewDelay);
        vm.prank(authority);
        distributor.finalizeSnapshot();

        bytes32[] memory aliceProof = new bytes32[](2);
        aliceProof[0] = bobLeaf;
        aliceProof[1] = carolLeaf;
        vm.prank(alice);
        assertEq(distributor.claim(1, aliceProof, alice), 33);

        vm.expectRevert(IProRataCollateralDistributor.ClaimsIncomplete.selector);
        distributor.sweepDust();

        bytes32[] memory bobProof = new bytes32[](2);
        bobProof[0] = aliceLeaf;
        bobProof[1] = carolLeaf;
        vm.prank(bob);
        assertEq(distributor.claim(1, bobProof, bob), 33);

        bytes32[] memory carolProof = new bytes32[](1);
        carolProof[0] = pair;
        vm.prank(carol);
        assertEq(distributor.claim(1, carolProof, carol), 33);

        assertEq(collateralAsset.balanceOf(address(distributor)), 1);

        assertEq(distributor.sweepDust(), 1);
        assertEq(collateralAsset.balanceOf(dustRecipient), 1);

        vm.expectRevert(IProRataCollateralDistributor.DustAlreadySwept.selector);
        distributor.sweepDust();
    }

    function testClaimRequiresFinalizedSnapshotAndRecipient() public {
        bytes32 leaf = _leaf(alice, 1 ether);
        _propose(leaf, 1 ether, 1 ether);

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(alice);
        vm.expectRevert(IProRataCollateralDistributor.SnapshotNotFinalized.selector);
        distributor.claim(1 ether, proof, alice);

        collateralAsset.mint(address(distributor), 1 ether);
        vm.warp(block.timestamp + reviewDelay);
        vm.prank(authority);
        distributor.finalizeSnapshot();

        vm.prank(alice);
        vm.expectRevert(IProRataCollateralDistributor.InvalidRecipient.selector);
        distributor.claim(1 ether, proof, address(0));
    }

    function _propose(bytes32 root, uint256 totalScaledDebt, uint256 collateralAmount) internal {
        vm.prank(authority);
        distributor.proposeSnapshot(
            market,
            block.number,
            totalScaledDebt,
            collateralAmount,
            root,
            keccak256("evidence"),
            block.timestamp + reviewDelay
        );
    }

    function _leaf(address account, uint256 scaledDebt) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(account, scaledDebt))));
    }

    function _root2(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return _hashPair(a, b);
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}
