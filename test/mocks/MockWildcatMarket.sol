// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import "v2-protocol/libraries/MarketState.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract MockWildcatMarket {
    MarketState internal _state;
    uint256 public lastAvailableLiquidity;
    uint128 public pendingNormalizedUnclaimed;
    uint128 public pendingAccruedProtocolFees;

    address public borrower;
    address public asset;
    uint256 public delinquencyGracePeriod;

    event Repayment(uint256 amount, uint256 batches);

    constructor(
        address _borrower,
        address _asset,
        uint256 _delinquencyGracePeriod
    ) {
        borrower = _borrower;
        asset = _asset;
        delinquencyGracePeriod = _delinquencyGracePeriod;
        _state.scaleFactor = 1e27;
        _state.reserveRatioBips = 10_000;
    }

    function currentState() public view returns (MarketState memory) {
        return _state;
    }

    function setState(MarketState memory state) public {
        _state = state;
    }

    function repayAndProcessUnpaidWithdrawalBatches(
        uint256 repayAmount,
        uint256 maxBatches
    ) public {
        if (repayAmount > 0) {
            bool success = MockERC20(asset).transferFrom(
                msg.sender,
                address(this),
                repayAmount
            );
            require(success, "TRANSFER_FAILED");
        }

        uint256 liabilities = uint256(_state.normalizedUnclaimedWithdrawals) +
            _state.accruedProtocolFees;

        liabilities += pendingNormalizedUnclaimed + pendingAccruedProtocolFees;

        uint256 availableLiquidity = totalAssets() - liabilities;
        lastAvailableLiquidity = availableLiquidity;

        emit Repayment(repayAmount, maxBatches);
    }

    function updateState() external {
        _state.normalizedUnclaimedWithdrawals += pendingNormalizedUnclaimed;
        _state.accruedProtocolFees += pendingAccruedProtocolFees;
        _state.scaledPendingWithdrawals = 0;
        pendingNormalizedUnclaimed = 0;
        pendingAccruedProtocolFees = 0;
    }

    function setPendingAccruals(
        uint128 normalizedUnclaimedDelta,
        uint128 accruedFeesDelta
    ) external {
        pendingNormalizedUnclaimed = normalizedUnclaimedDelta;
        pendingAccruedProtocolFees = accruedFeesDelta;
    }

    function totalAssets() public view returns (uint256) {
        return MockERC20(asset).balanceOf(address(this));
    }

    function setAccountingState(uint128 normalizedUnclaimedWithdrawals, uint128 accruedProtocolFees) external {
        _state.normalizedUnclaimedWithdrawals = normalizedUnclaimedWithdrawals;
        _state.accruedProtocolFees = accruedProtocolFees;
    }

    function isClosed() public view returns (bool) {
        return _state.isClosed;
    }

    function setState(
        uint256 debt,
        uint256 assets,
        bool isDelinquent,
        uint32 timeDelinquent,
        bool _isClosed
    ) external {
        _state.scaledTotalSupply = uint104(debt);
        uint currentBalance = MockERC20(asset).balanceOf(address(this));
        if (currentBalance > 0) {
            MockERC20(asset).burn(address(this), currentBalance);
        }
        MockERC20(asset).mint(address(this), assets);
        _state.isDelinquent = isDelinquent;
        _state.timeDelinquent = timeDelinquent;
        _state.isClosed = _isClosed;
    }
}
