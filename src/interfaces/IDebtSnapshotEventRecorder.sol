// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

interface IDebtSnapshotEventRecorder {
    enum MovementKind {
        Deposit,
        Transfer,
        QueueWithdrawal
    }

    event ScaledDebtMovement(
        address indexed market, address indexed from, address indexed to, uint256 scaledAmount, MovementKind kind
    );

    error InvalidMarket();
    error InvalidRecorder();
    error CallerNotRecorder();
    error InvalidAccount();
    error InvalidTransfer();
    error InvalidScaledAmount();

    function recordDeposit(address account, uint256 scaledAmount) external;

    function recordTransfer(address from, address to, uint256 scaledAmount) external;

    function recordQueuedWithdrawal(address account, uint256 scaledAmount) external;
}
