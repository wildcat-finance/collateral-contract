// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import {IDebtSnapshotEventRecorder} from "./interfaces/IDebtSnapshotEventRecorder.sol";

contract DebtSnapshotEventRecorder is IDebtSnapshotEventRecorder {
    address public immutable market;
    address public immutable recorder;

    modifier onlyRecorder() {
        if (msg.sender != recorder) revert CallerNotRecorder();
        _;
    }

    constructor(address market_, address recorder_) {
        if (market_ == address(0)) revert InvalidMarket();
        if (recorder_ == address(0)) revert InvalidRecorder();

        market = market_;
        recorder = recorder_;
    }

    function recordDeposit(address account, uint256 scaledAmount) external onlyRecorder {
        if (account == address(0)) revert InvalidAccount();
        if (scaledAmount == 0) revert InvalidScaledAmount();

        emit ScaledDebtMovement(market, address(0), account, scaledAmount, MovementKind.Deposit);
    }

    function recordTransfer(address from, address to, uint256 scaledAmount) external onlyRecorder {
        if (from == address(0) || to == address(0)) revert InvalidTransfer();
        if (from == to) revert InvalidTransfer();
        if (scaledAmount == 0) revert InvalidScaledAmount();

        emit ScaledDebtMovement(market, from, to, scaledAmount, MovementKind.Transfer);
    }

    function recordQueuedWithdrawal(address account, uint256 scaledAmount) external onlyRecorder {
        if (account == address(0)) revert InvalidAccount();
        if (scaledAmount == 0) revert InvalidScaledAmount();

        emit ScaledDebtMovement(market, account, address(0), scaledAmount, MovementKind.QueueWithdrawal);
    }
}
