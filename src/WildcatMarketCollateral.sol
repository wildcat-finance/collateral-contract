// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import './libraries/LibERC20.sol';
import './libraries/FunctionTypeCasts.sol';

interface IWildcatMarket {
    function asset() external view returns (address);
    function delinquencyGracePeriod() external view returns (uint);
    function isClosed() external view returns (bool);
    function borrower() external view returns (address);
    function repayAndProcessUnpaidWithdrawalBatches(uint256 repayAmount, uint256 maxBatches) external;
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

    uint public immutable liquidationCooldown;
    uint public nextLiquidationTrigger;

    // factory address that deployed the collateral contract
    address public immutable factory;

    event CollateralDeposited(address, address, uint, uint);
    event CollateralReclaimed(address, address, uint, uint);
    event CollateralRepaid(address, uint, uint);

    error BadRescueAttempt(address);
    error BebopPMMQuoteFailed(bytes);

    // Use this to store the list of unique depositors to a market
    mapping(address => bool) public hasDeposited;
    address[] public depositors;
    mapping(address => uint) public depositorAmounts;

    modifier onlyBorrower() {
        require(msg.sender == marketBorrower);
        _;
    }

    modifier onlyBacker() {
        require(hasDeposited[msg.sender]);
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

    // TODO: Dillon please sanity check this
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

      liquidationCooldown = underlyingMarket.delinquencyGracePeriod();
      nextLiquidationTrigger = block.timestamp;

    }

    function _updateBackerList(address _backer) internal {
        if (!hasDeposited[_backer]) {
            depositors.push(_backer);
        }
    }

    function deposit(uint amount) public returns (bool) {
        // Transfer deposit from caller
        collateralAsset.safeTransferFrom(msg.sender, address(this), amount);
        _updateBackerList(msg.sender);
        depositorAmounts[msg.sender] += amount;

        emit CollateralDeposited(msg.sender, address(this), amount, block.timestamp);
        return true;
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

function processBackingReduction(uint _before, uint _after) internal {
        require(_before > 0, "Before amount must be greater than zero");
        require(_after <= _before, "After amount must be less than or equal to before amount");

        // Use fixed-point arithmetic to avoid precision loss
        uint reductionFactor = (_after * 1e18) / _before;

        for (uint i = 0; i < depositors.length; i++) {
            address depositor = depositors[i];
            uint oldAmount = depositorAmounts[depositor];
            uint newAmount = (oldAmount * reductionFactor) / 1e18;
            depositorAmounts[depositor] = newAmount;
        }
    }
    
    // Sells collateral and repays delinquent debt of the market through Bebop PMM
    // Requires that the underlying token is supported by Bebop PMM via this list:
    // https://api.bebop.xyz/pmm/ethereum/v3/token-info
    function liquidateCollateral(
        bytes calldata _quoteCalldata,
        uint lengthWithdrawalQueue
    ) public returns (uint availableToRepay) {

        bool marketInPenalty = true; // TODO: replace this with an 'is in penalty' check

        require(marketInPenalty, "Market is not in penalty state!");

        // TODO: do we want to keep this cooldown? Seems like it's a fair balance to
        // allow people to tap it periodically but not constantly, it's not like any
        // backer can pull the assets out without terminating the market.
        require(block.timestamp >= nextLiquidationTrigger, "Liquidator in cooldown!");

        uint beforeBalance = collateralAsset.balanceOf(address(this));

        (bool success, bytes memory data) = bebopSettlementContract.call(_quoteCalldata);

        if (!success) { revert BebopPMMQuoteFailed(data); }
    
        uint afterBalance = collateralAsset.balanceOf(address(this));

        availableToRepay = underlyingAsset.balanceOf(address(this));

        // Transfer to/process underlying market to transfer new funds to reserved assets pool
        underlyingAsset.safeTransferAll(address(underlyingMarket));
        underlyingMarket.repayAndProcessUnpaidWithdrawalBatches(0, lengthWithdrawalQueue);

        nextLiquidationTrigger = block.timestamp + liquidationCooldown;

        // Reduce each depositors' backing by the relative percentage backing was liquidated.
        processBackingReduction(beforeBalance, afterBalance);

        emit CollateralRepaid(address(underlyingMarket), availableToRepay, block.timestamp);
    }

    // TODO: ADD RE-ENTRANCY THROUGHOUT
    function reclaimCollateral() public onlyBacker() {
        require(underlyingMarket.isClosed(), "Market not terminated!");

        uint reclaimAmount = depositorAmounts[msg.sender];
        depositorAmounts[msg.sender] = 0;

        require(reclaimAmount > 0, "Nothing to reclaim!");
        collateralAsset.safeTransferFrom(address(this), msg.sender, reclaimAmount);

        emit CollateralReclaimed(address(this), msg.sender, reclaimAmount, block.timestamp);
    }

}
