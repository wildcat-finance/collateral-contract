// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import "forge-std/Test.sol";

import {DebtSnapshotEventRecorder} from "src/DebtSnapshotEventRecorder.sol";
import {IDebtSnapshotEventRecorder} from "src/interfaces/IDebtSnapshotEventRecorder.sol";

contract DebtSnapshotEventRecorderTest is Test {
    DebtSnapshotEventRecorder recorder;

    address market = address(0x1234);
    address hook = address(0xB00C);
    address alice = address(0xA);
    address bob = address(0xB);

    function setUp() public {
        recorder = new DebtSnapshotEventRecorder(market, hook);
    }

    function testConstructorValidation() public {
        vm.expectRevert(IDebtSnapshotEventRecorder.InvalidMarket.selector);
        new DebtSnapshotEventRecorder(address(0), hook);

        vm.expectRevert(IDebtSnapshotEventRecorder.InvalidRecorder.selector);
        new DebtSnapshotEventRecorder(market, address(0));
    }

    function testOnlyRecorderCanEmitMovements() public {
        vm.expectRevert(IDebtSnapshotEventRecorder.CallerNotRecorder.selector);
        recorder.recordDeposit(alice, 1);

        vm.prank(hook);
        recorder.recordDeposit(alice, 1);
    }

    function testRecordDeposit() public {
        vm.expectEmit(true, true, true, true, address(recorder));
        emit IDebtSnapshotEventRecorder.ScaledDebtMovement(
            market, address(0), alice, 100, IDebtSnapshotEventRecorder.MovementKind.Deposit
        );

        vm.prank(hook);
        recorder.recordDeposit(alice, 100);
    }

    function testRecordTransfer() public {
        vm.expectEmit(true, true, true, true, address(recorder));
        emit IDebtSnapshotEventRecorder.ScaledDebtMovement(
            market, alice, bob, 40, IDebtSnapshotEventRecorder.MovementKind.Transfer
        );

        vm.prank(hook);
        recorder.recordTransfer(alice, bob, 40);
    }

    function testRecordQueuedWithdrawal() public {
        vm.expectEmit(true, true, true, true, address(recorder));
        emit IDebtSnapshotEventRecorder.ScaledDebtMovement(
            market, alice, address(0), 25, IDebtSnapshotEventRecorder.MovementKind.QueueWithdrawal
        );

        vm.prank(hook);
        recorder.recordQueuedWithdrawal(alice, 25);
    }

    function testRejectsInvalidMovements() public {
        vm.startPrank(hook);

        vm.expectRevert(IDebtSnapshotEventRecorder.InvalidAccount.selector);
        recorder.recordDeposit(address(0), 1);

        vm.expectRevert(IDebtSnapshotEventRecorder.InvalidScaledAmount.selector);
        recorder.recordDeposit(alice, 0);

        vm.expectRevert(IDebtSnapshotEventRecorder.InvalidTransfer.selector);
        recorder.recordTransfer(address(0), bob, 1);

        vm.expectRevert(IDebtSnapshotEventRecorder.InvalidTransfer.selector);
        recorder.recordTransfer(alice, alice, 1);

        vm.expectRevert(IDebtSnapshotEventRecorder.InvalidScaledAmount.selector);
        recorder.recordTransfer(alice, bob, 0);

        vm.expectRevert(IDebtSnapshotEventRecorder.InvalidAccount.selector);
        recorder.recordQueuedWithdrawal(address(0), 1);

        vm.expectRevert(IDebtSnapshotEventRecorder.InvalidScaledAmount.selector);
        recorder.recordQueuedWithdrawal(alice, 0);

        vm.stopPrank();
    }
}
