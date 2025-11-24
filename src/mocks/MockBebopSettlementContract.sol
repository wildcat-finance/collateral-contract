// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract MockBebopSettlementContract {
    function execute(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOut,
        bool shouldRevert
    ) external {
        assembly {
            if shouldRevert {
                revert(0, 0)
            }
        }
        MockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(tokenOut).mint(msg.sender, amountOut);
    }
}
