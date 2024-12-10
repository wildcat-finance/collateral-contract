// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import './libraries/LibERC20.sol';
import './libraries/FunctionTypeCasts.sol';

interface IWildcatMarket {
    function repayAndProcessUnpaidWithdrawalBatches(uint256 repayAmount, uint256 maxBatches) external;
    function owner() external view returns (address);
    function isClosed() external view returns (bool);
    function asset() external view returns (address);
}

contract WildcatMarketCollateral {
    using LibERC20 for address;
    using FunctionTypeCasts for *;

    address public immutable collateralAsset;
    IWildcatMarket public immutable underlyingMarket;
    address public immutable marketBorrower;

    address public immutable underlyingAsset;

    // factory address that deployed the collateral contract
    address public immutable factory;

    event CollateralDeposited(address, address, uint, uint);
    event CollateralReclaimed(address, address, uint, uint);

    modifier onlyBorrower() {
        require(msg.sender == marketBorrower);
        _;
    }

    function _getCollateralParameters() internal view returns (uint256 collateralParametersPointer) {
        assembly {
        collateralParametersPointer := mload(0x40)
        // one word worth of space for three addresses in the struct: 96 bytes = 0x60
        mstore(0x40, add(collateralParametersPointer, 0x60))
        // Write the selector for IHooksFactory.getMarketParameters
        mstore(0x00, 0x04032dbb)
        // Call `getCollateralParameters` and copy the returned struct to the allocated memory
        // buffer, reverting if the call fails or does not return the correct amount of bytes.
        // This overrides all the ABI decoding safety checks, as the call is always made to
        // the factory contract which will only ever return the prepared market parameters.
        if iszero(
            and(
            eq(returndatasize(), 0x60),
            staticcall(gas(), caller(), 0x1c, 0x04, collateralParametersPointer, 0x60)
            )
        ) {
            revert(0, 0)
        }
        }
    }

    constructor() {
      
      factory = msg.sender;

      CollateralParameters memory parameters =
        _getCollateralParameters.asReturnsCollateralParameters()();

      // Set asset metadata
      collateralAsset = parameters.collateralToken;
      underlyingMarket = IWildcatMarket(parameters.associatedMarket);
      marketBorrower = parameters.borrower;

      underlyingAsset = underlyingMarket.asset();

    }

    function deposit(uint amount) public onlyBorrower() {

        // Transfer deposit from caller
        collateralAsset.safeTransferFrom(msg.sender, address(this), amount);

        emit CollateralDeposited(msg.sender, address(this), amount, block.timestamp);
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
        require(underlyingMarket.isClosed(), "Market not terminated!");

        // total amount that's in the wallet
        uint reclaimAmount = underlyingAsset.balanceOf(address(this));

        collateralAsset.safeTransferFrom(address(this), msg.sender, reclaimAmount);

        emit CollateralReclaimed(address(this), msg.sender, reclaimAmount, block.timestamp);
    }

}
