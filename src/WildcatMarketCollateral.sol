// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import './libraries/LibERC20.sol';
import './libraries/FunctionTypeCasts.sol';

interface IWildcatMarket {
    function repayAndProcessUnpaidWithdrawalBatches(uint256 repayAmount, uint256 maxBatches) external;
    function isClosed() external view returns (bool);
    function owner() external view returns (address); // used by the factory
    function asset() external view returns (address);
}

contract WildcatMarketCollateral {
    using LibERC20 for address;
    using FunctionTypeCasts for *;

    address public immutable collateralAsset;
    IWildcatMarket public immutable underlyingMarket;
    address public immutable marketBorrower;

    address public immutable underlyingAsset;

    address public immutable bebopSettlementContract =
      0xbbbbbBB520d69a9775E85b458C58c648259FAD5F;

    // factory address that deployed the collateral contract
    address public immutable factory;

    event CollateralDeposited(address, address, uint, uint);
    event CollateralReclaimed(address, address, uint, uint);
    event CollateralRepaid(uint);

    error BadRescueAttempt(address);
    error BebopPMMQuoteFailed(bytes);

    modifier onlyBorrower() {
        require(msg.sender == marketBorrower);
        _;
    }

    /**
     * @dev Return the contract name "WildcatCollateralContractV1"
     */
    function name() external pure returns (string memory) {
        // Use yul to avoid duplicate memory allocation and reduce code size
        // Uses words at 0x20, 0x40, 0x60
        // 0x20 is overwritten with the ABI offset (32)
        // 0x40 contains the free pointer which will be 1 byte when this function executes.
        // The length of the string (27) is written to the last byte of the free pointer word.
        // 0x60 is the zero slot, so it will not have any dirty bits when this function executes.
        // It is overwritten with the name bytes in the same operation as the length.
        assembly {
        mstore(0x53, 0x1b57696c64636174436f6c6c61746572616c436f6e74726163745631)
        mstore(0x20, 0x20)
        return(0x20, 0x60)
        }
    }

    function _getCollateralParameters() internal view returns (uint256 collateralParametersPointer) {
        assembly {
        collateralParametersPointer := mload(0x40)
        // one word worth of space for three addresses in the struct: 96 bytes = 0x60
        mstore(0x40, add(collateralParametersPointer, 0x60))
        // Write the selector for WildcatMarketCollateralFactory.getCollateralParameters
        mstore(0x00, 0x5d861505)
        // Call `getCollateralParameters` and copy the returned struct to the allocated memory
        // buffer, reverting if the call fails or does not return the correct amount of bytes.
        // This overrides all the ABI decoding safety checks, as the call is always made to
        // the factory contract which will only ever return the prepared collateral parameters.
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

    /**
    * @dev Token rescue function for recovering tokens sent to the contract
    *      contract by mistake or otherwise outside of the normal course of
    *      operation.
    */
    function rescueTokens(address token) public onlyBorrower() {
      if ((token == underlyingAsset) || (token == address(this))) {
        revert BadRescueAttempt(token);
      }

      token.safeTransferAll(msg.sender);
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
    function liquidateCollateral(
        bytes calldata _quoteCalldata,
        uint lengthWithdrawalQueue
    ) public returns (uint availableToRepay) {
        (bool success, bytes memory data) = bebopSettlementContract.call(_quoteCalldata);

        if (!success) { revert BebopPMMQuoteFailed(data); }
    
        availableToRepay = collateralAsset.balanceOf(address(this));

        collateralAsset.safeTransferAll(address(underlyingMarket));

        // Process underlying market to transfer new funds to reserved assets pool
        underlyingMarket.repayAndProcessUnpaidWithdrawalBatches(0, lengthWithdrawalQueue);

        emit CollateralRepaid(availableToRepay);
    }

    function reclaimCollateral() public onlyBorrower() {
        require(underlyingMarket.isClosed(), "Market not terminated!");

        // total amount that's in the wallet
        uint reclaimAmount = underlyingAsset.balanceOf(address(this));

        collateralAsset.safeTransferFrom(address(this), msg.sender, reclaimAmount);

        emit CollateralReclaimed(address(this), msg.sender, reclaimAmount, block.timestamp);
    }

}
