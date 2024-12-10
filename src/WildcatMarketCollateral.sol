// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import './libraries/LibERC20.sol';

interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IWildcatMarket {
    function repayAndProcessUnpaidWithdrawalBatches(uint256 repayAmount, uint256 maxBatches) external;
    function owner() external view returns (address);
    function isClosed() external view returns (bool);
    function asset() external view returns (address);
}

contract WildcatMarketCollateral {

    IERC20 public immutable collateralAsset;
    IWildcatMarket public immutable underlyingMarket;

    // owner of collateral contract and underlying market will always match
    address public immutable marketBorrower;

    modifier onlyBorrower() {
        require(msg.sender == marketBorrower);
        _;
    }

    constructor() {
        // need to fetch collateral and underlying market addresses from the factory
        // the borrower itself is going to be msg.sender
    }

    function deposit(uint amount) public onlyBorrower() {

        // Transfer deposit from caller
        collateralAsset.safeTransferFrom(msg.sender, address(this), amount);

        emit CollateralDeposited();
    }

    // Permits recovery of ERC-20s that aren't the collateral asset
    function rescueFunds() public onlyBorrower() {
    }
    
    // Sells and transfers up to the delinquent debt of the market
    // This is going to need us to decide what meta-aggregator we use and how, which
    //   means that there'll be more arguments here (i.e. a bytes32 data).
    // 'Problem' is that if we want to use 1inch or something we're going to need
    //   off-chain data from their API to determine where to route towards.
    // 
    // We can do this in two steps if we want to use intents, but that means there
    // needs to be a liquidate function and then a separate repay function, which
    // doesn't work if we're only liquidating precisely up to what is needed: there
    // will be some dust left over. That means we probably need to liquidate a few
    // bips higher, in the same way as we need to do approvals in V1 through the UI.
    function liquidateCollateral(uint marketDelinquentDebt) public returns (uint) {
    }

    function reclaimCollateral() public onlyBorrower() {

    }

}
