// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {DebtSnapshotEventRecorder} from "src/DebtSnapshotEventRecorder.sol";
import {IDebtSnapshotEventRecorder} from "src/interfaces/IDebtSnapshotEventRecorder.sol";
import {ProRataCollateralDistributor} from "src/ProRataCollateralDistributor.sol";

contract ProRataCollateralReleaseDemoTest is Test {
    MockERC20 collateralAsset;
    DebtSnapshotEventRecorder recorder;
    ProRataCollateralDistributor distributor;

    address market = address(0x1234);
    address hook = address(0xB00C);
    address authority = address(0xA11CE);
    address dustRecipient = address(0xD057);
    address alice = address(0xA);
    address bob = address(0xB);
    address carol = address(0xC);
    uint256 reviewDelay = 1 days;

    function setUp() public {
        collateralAsset = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        recorder = new DebtSnapshotEventRecorder(market, hook);
        distributor =
            new ProRataCollateralDistributor(address(collateralAsset), market, authority, dustRecipient, reviewDelay);
    }

    function testEndToEndCollateralReleaseFromReconciledEvents() public {
        vm.recordLogs();

        uint256 aliceScaledDebt;
        uint256 bobScaledDebt;
        uint256 carolScaledDebt;

        vm.prank(hook);
        recorder.recordDeposit(alice, 60);
        aliceScaledDebt += 60;

        vm.prank(hook);
        recorder.recordDeposit(bob, 50);
        bobScaledDebt += 50;

        vm.prank(hook);
        recorder.recordTransfer(alice, carol, 20);
        aliceScaledDebt -= 20;
        carolScaledDebt += 20;

        vm.prank(hook);
        recorder.recordQueuedWithdrawal(bob, 10);
        bobScaledDebt -= 10;

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 4);
        assertEq(entries[0].topics[0], IDebtSnapshotEventRecorder.ScaledDebtMovement.selector);

        uint256 snapshotBlock = block.number;
        uint256 totalScaledDebt = aliceScaledDebt + bobScaledDebt + carolScaledDebt;
        uint256 collateralAmount = 100 ether;

        bytes32 aliceLeaf = _leaf(alice, aliceScaledDebt);
        bytes32 bobLeaf = _leaf(bob, bobScaledDebt);
        bytes32 carolLeaf = _leaf(carol, carolScaledDebt);
        bytes32 pair = _hashPair(aliceLeaf, bobLeaf);
        bytes32 root = _hashPair(pair, carolLeaf);

        collateralAsset.mint(address(distributor), collateralAmount);

        vm.prank(authority);
        distributor.proposeSnapshot(
            market,
            snapshotBlock,
            totalScaledDebt,
            collateralAmount,
            root,
            keccak256("reconciled event bundle"),
            block.timestamp + reviewDelay
        );

        vm.warp(block.timestamp + reviewDelay);

        vm.prank(authority);
        distributor.finalizeSnapshot();

        bytes32[] memory aliceProof = new bytes32[](2);
        aliceProof[0] = bobLeaf;
        aliceProof[1] = carolLeaf;
        vm.prank(alice);
        assertEq(distributor.claim(aliceScaledDebt, aliceProof, alice), 40 ether);

        bytes32[] memory bobProof = new bytes32[](2);
        bobProof[0] = aliceLeaf;
        bobProof[1] = carolLeaf;
        vm.prank(bob);
        assertEq(distributor.claim(bobScaledDebt, bobProof, bob), 40 ether);

        bytes32[] memory carolProof = new bytes32[](1);
        carolProof[0] = pair;
        vm.prank(carol);
        assertEq(distributor.claim(carolScaledDebt, carolProof, carol), 20 ether);

        assertEq(collateralAsset.balanceOf(alice), 40 ether);
        assertEq(collateralAsset.balanceOf(bob), 40 ether);
        assertEq(collateralAsset.balanceOf(carol), 20 ether);
        assertEq(collateralAsset.balanceOf(address(distributor)), 0);
    }

    function _leaf(address account, uint256 scaledDebt) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(account, scaledDebt))));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}
