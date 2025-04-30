// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {MarketState} from "v2-protocol/libraries/MarketState.sol";

interface IWildcatMarket {
    function asset() external view returns (address);

    function delinquencyGracePeriod() external view returns (uint);

    function isClosed() external view returns (bool);

    function borrower() external view returns (address);

    function currentState() external view returns (MarketState memory);

    function repayAndProcessUnpaidWithdrawalBatches(
        uint256 repayAmount,
        uint256 maxBatches
    ) external;
}
