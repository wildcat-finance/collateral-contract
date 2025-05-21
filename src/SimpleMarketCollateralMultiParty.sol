// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import "./libraries/LibERC20.sol";
import "./libraries/FunctionTypeCasts.sol";
import {WildcatMarketCollateralFactory} from "./WildcatMarketCollateralFactory.sol";
import "v2-protocol/libraries/MarketState.sol";
import "./interfaces/IWildcatMarket.sol";
import "v2-protocol/ReentrancyGuard.sol";
import "solady/utils/FixedPointMathLib.sol";

using MathUtils for uint256;
using SafeCastLib for uint256;

struct Depositor {
    uint224 shares;
    uint32 lastDepositIndex;
}

/// @title SimpleMarketCollateralMultiParty
/// @notice A basic collateral contract for Wildcat markets that supports multiple depositors.
///
///         Users deposit a collateral asset which can be liquidated when the underlying market is in
///         penalized delinquency. Liquidations are processed through the Bebop PMM by accounts with a
///         liquidator role managed by the arch-controller owner. The liquidator provides the calldata
///         for the swap and thus the terms of the swap (minimum output, maximum input, etc.)
///
///         Note: This carries the inherent risk that a malicious executor in collaboration with a malicious
///         maker on Bebop could steal user funds by processing a liquidation at a poor price.
///
///         Deposits are indexed with an incrementing value mapped to the depositor.
///         When the contract's collateral is fully liquidated, the index of the most recent deposit is written to
///         `lastFullLiquidationDepositIndex` and the `totalShares` is set to 0. Any depositors with a deposit index
///         less than or equal to `lastFullLiquidationDepositIndex` will have their shares reset to 0.
///         This ensures that depositors whose collateral has been fully liquidated do not have any remaining ownership
///         of the contract's collateral when other depositors make new deposits.
///
///         If tokens are sent to the contract by mistake, the borrower can rescue them using the `rescueTokens` function.
///         The contract internally tracks the amount of the collateral asset that it has as the difference between the total
///         deposited and the total liquidated / withdrawn. If the contract has an excess balance of the collateral asset, it
///         can be rescued by the borrower.
///
///         Note: This contract does not support rebasing tokens or other assets with non-standard transfer
///         semantics due to its use of internal balance tracking rather than the ERC20 `balanceOf` function.
contract SimpleMarketCollateralMultiParty is ReentrancyGuard {
    using LibERC20 for address;
    using FunctionTypeCasts for *;

    /// @dev The index of the last deposit that was fully liquidated.
    uint32 public lastFullLiquidationDepositIndex;
    uint32 public nextDepositIndex;

    mapping(address account => Depositor depositor) internal _depositors;

    function _getDepositor(
        address account
    ) internal returns (Depositor storage depositor) {
        depositor = _depositors[account];
        if (depositor.lastDepositIndex <= lastFullLiquidationDepositIndex) {
            emit LiquidatedSharesReset(account, depositor.shares);
            depositor.shares = 0;
            depositor.lastDepositIndex = 0;
        }
    }

    /// @dev Returns the active shares of an account.
    function sharesOf(address account) public view returns (uint256) {
        Depositor memory depositor = _depositors[account];
        if (depositor.lastDepositIndex <= lastFullLiquidationDepositIndex) {
            return 0;
        }
        return depositor.shares;
    }

    function getDepositor(
        address account
    ) public view returns (Depositor memory depositor) {
        depositor = _depositors[account];
        if (depositor.lastDepositIndex <= lastFullLiquidationDepositIndex) {
            depositor.shares = 0;
            depositor.lastDepositIndex = 0;
        }
    }

    /// @dev The total active (unwithdrawn) shares of the contract.
    uint224 public totalShares;
    /// @dev The total amount of collateral that is available to be liquidated or reclaimed.
    uint256 public availableCollateral;

    // factory address that deployed the collateral contract
    address public immutable factory;
    address public immutable collateralAsset;
    IWildcatMarket public immutable market;
    address public immutable marketBorrower;

    address public immutable underlyingAsset;

    address public immutable bebopSettlementContract =
        0xbbbbbBB520d69a9775E85b458C58c648259FAD5F;

    uint32 public immutable liquidationCooldown;

    /// @dev The maximum repayment as a fraction of the delinquent debt
    ///      105% means that the market can repay up to 5% more than the delinquent debt
    uint16 public immutable maxRepaymentBips = 10_500; // 105%

    uint32 public nextLiquidationTrigger;

    event CollateralDeposited(
        address depositor,
        uint256 depositAmount,
        uint256 sharesMinted,
        uint256 depositIndex
    );
    event CollateralReclaimed(
        address reclaimant,
        uint256 sharesBurned,
        uint256 amountReclaimed
    );
    event Liquidation(
        address liquidator,
        uint256 collateralLiquidated,
        uint256 underlyingReceived
    );
    event UnderlyingAssetSentToMarket(uint256 amountSent);
    event TokenRescued(address token, uint256 amountRescued);
    event FullLiquidation(uint32 lastFullLiquidationDepositIndex);
    event LiquidatedSharesReset(address account, uint256 sharesReset);

    error BadRescueAttempt(address token);
    error BebopSwapFailed(bytes returnData);
    error InsufficientSwapOutput();
    error CallerNotApprovedExecutor();
    error CallerNotBorrower();
    error MarketNotInPenalty();
    error MaxRepaymentExceeded();
    error MarketNotTerminated();
    error MarketTerminated();
    error LiquidationInCooldown();
    error ZeroTokenBalance();
    error ZeroShares();
    error ZeroReclaimAmount();
    error ZeroDepositAmount();
    error DivFailed();
    error InsufficientCollateral();

    modifier onlyBorrower() {
        if (msg.sender != marketBorrower) {
            revert CallerNotBorrower();
        }
        _;
    }

    modifier onlyApprovedExecutor() {
        if (
            !WildcatMarketCollateralFactory(factory).isApprovedExecutor(
                msg.sender
            )
        ) {
            revert CallerNotApprovedExecutor();
        }
        _;
    }

    modifier marketClosed() {
        if (!market.isClosed()) {
            revert MarketNotTerminated();
        }
        _;
    }

    modifier marketOpen() {
        if (market.isClosed()) {
            revert MarketTerminated();
        }
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
            mstore(
                0x53,
                0x1b57696c64636174436f6c6c61746572616c436f6e74726163745631
            )
            mstore(0x20, 0x20)
            return(0x20, 0x60)
        }
    }

    function _getCollateralParameters()
        internal
        view
        returns (uint256 collateralParametersPointer)
    {
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
                    staticcall(
                        gas(),
                        caller(),
                        0x1c,
                        0x04,
                        collateralParametersPointer,
                        0x60
                    )
                )
            ) {
                revert(0, 0)
            }
        }
    }

    constructor() {
        factory = msg.sender;

        CollateralParameters memory parameters = _getCollateralParameters
            .asReturnsCollateralParameters()();

        // Set asset metadata
        collateralAsset = parameters.collateralToken;
        market = IWildcatMarket(parameters.associatedMarket);
        marketBorrower = parameters.borrower;

        underlyingAsset = market.asset();

        liquidationCooldown = market.delinquencyGracePeriod().toUint32();
    }

    function deposit(
        uint256 _amount
    ) public marketOpen nonReentrant returns (bool) {
        if (_amount == 0) revert ZeroDepositAmount();

        uint256 depositAmount = _amount.toUint248();
        uint224 shares = (
            (availableCollateral == 0 || totalShares == 0)
                ? depositAmount
                : FixedPointMathLib.fullMulDiv(
                    depositAmount,
                    totalShares,
                    availableCollateral
                )
        ).toUint224();
        if (shares == 0) revert ZeroShares();

        collateralAsset.safeTransferFrom(
            msg.sender,
            address(this),
            depositAmount
        );

        Depositor storage depositor = _getDepositor(msg.sender);
        depositor.shares += shares;
        uint32 index = ++nextDepositIndex;
        depositor.lastDepositIndex = index;
        totalShares += shares;
        availableCollateral += depositAmount;

        emit CollateralDeposited(msg.sender, depositAmount, shares, index);
        return true;
    }

    /**
     * @dev Token rescue function for recovering tokens sent to the contract
     *      contract by mistake or otherwise outside of the normal course of
     *      operation.
     *
     *      Only the borrower can rescue tokens from the contract.
     *
     *      The underlying asset can only be rescued if the market is closed; if the market
     *      is open, any balance in the underlying asset is transferred to the market.
     *
     *      The collateral asset can be rescued if the balance is greater than the expected available collateral.
     */
    function rescueTokens(address token) public onlyBorrower nonReentrant {
        uint256 tokenBalance = token.balanceOf(address(this));
        // The collateral asset can only be rescued if the balance is greater than the expected available collateral.
        if (token == collateralAsset) {
            tokenBalance = tokenBalance.satSub(availableCollateral);
        }

        if (tokenBalance == 0) revert ZeroTokenBalance();

        // The liquidation process will always repay 100% of underlying assets received from bebop;
        // however, if the market is open and the underlying token is sent by mistake, it will simply
        // be sent to the market and treated as a repayment.
        if (token == underlyingAsset) {
            if (!market.isClosed()) {
                underlyingAsset.safeTransfer(address(market), tokenBalance);
                market.repayAndProcessUnpaidWithdrawalBatches(0, 0);
                emit UnderlyingAssetSentToMarket(tokenBalance);
                return;
            }
        }

        token.safeTransfer(msg.sender, tokenBalance);
        emit TokenRescued(token, tokenBalance);
    }

    function getMarketDelinquencyStatus()
        public
        view
        returns (bool marketInPenalty, uint256 delinquentDebt)
    {
        MarketState memory state = market.currentState();
        if (state.isClosed) revert MarketTerminated();

        // Check whether market delinquency timer is past the grace period
        marketInPenalty = state.timeDelinquent > liquidationCooldown;

        uint256 coverageLiquidity = state.liquidityRequired();
        uint256 marketTotalAssets = underlyingAsset.balanceOf(address(market));

        delinquentDebt = coverageLiquidity.satSub(marketTotalAssets);
    }

    /// @dev Sells collateral and repays delinquent debt of the market through Bebop PMM
    ///      Requires that the underlying token is supported by Bebop PMM via this list:
    ///      https://api.bebop.xyz/pmm/ethereum/v3/token-info
    ///
    /// NOTE: The amount of the underlying asset received MUST NOT exceed the market's
    ///       delinquent debt multiplied by the max repayment fraction.
    ///
    /// @param quoteCalldata The calldata for the Bebop PMM quote
    /// @param lengthWithdrawalQueue The number of withdrawal batches to process
    /// @param maxCollateralToLiquidate The maximum amount of collateral to liquidate
    /// @param minUnderlyingOut The minimum amount of underlying asset to receive
    function liquidateCollateral(
        bytes calldata quoteCalldata,
        uint lengthWithdrawalQueue,
        uint maxCollateralToLiquidate,
        uint minUnderlyingOut
    )
        public
        onlyApprovedExecutor
        nonReentrant
        returns (uint underlyingAmountReceived)
    {
        (
            bool marketInPenalty,
            uint delinquentDebt
        ) = getMarketDelinquencyStatus();

        // Ensure the market is in penalty state, there is no active cooldown, and
        // there is enough collateral for the liquidation
        if (!marketInPenalty || delinquentDebt == 0)
            revert MarketNotInPenalty();
        if (block.timestamp < nextLiquidationTrigger)
            revert LiquidationInCooldown();
        if (maxCollateralToLiquidate > availableCollateral)
            revert InsufficientCollateral();

        // Calculate the maximum repayment amount
        uint maxRepayment = delinquentDebt.bipMul(maxRepaymentBips);

        // Approve the Bebop settlement contract to spend the collateral
        collateralAsset.safeApprove(
            address(bebopSettlementContract),
            maxCollateralToLiquidate
        );

        uint beforeBalance = collateralAsset.balanceOf(address(this));
        (bool success, bytes memory data) = bebopSettlementContract.call(
            quoteCalldata
        );
        if (!success) revert BebopSwapFailed(data);
        collateralAsset.safeApprove(address(bebopSettlementContract), 0);

        uint afterBalance = collateralAsset.balanceOf(address(this));

        underlyingAmountReceived = underlyingAsset.balanceOf(address(this));

        if (underlyingAmountReceived < minUnderlyingOut)
            revert InsufficientSwapOutput();

        if (underlyingAmountReceived > maxRepayment)
            revert MaxRepaymentExceeded();

        // Transfer underlying asset to the market and process repayment.
        underlyingAsset.safeTransfer(address(market), underlyingAmountReceived);
        market.repayAndProcessUnpaidWithdrawalBatches(0, lengthWithdrawalQueue);

        nextLiquidationTrigger =
            block.timestamp.toUint32() +
            liquidationCooldown;

        uint collateralLiquidated = beforeBalance - afterBalance;
        emit Liquidation(
            msg.sender,
            collateralLiquidated,
            underlyingAmountReceived
        );

        availableCollateral -= collateralLiquidated;

        // If the contract has no available collateral, reset the shares and last liquidated deposit index
        // to avoid inflating the share price of future deposits. Any deposits prior to the last full
        // liquidation will have their shares reset to 0.
        if (availableCollateral == 0) {
            totalShares = 0;
            lastFullLiquidationDepositIndex = nextDepositIndex;
            emit FullLiquidation(lastFullLiquidationDepositIndex);
        }
    }

    function reclaimCollateral() public marketClosed nonReentrant {
        Depositor storage depositor = _getDepositor(msg.sender);

        uint224 shares = depositor.shares;
        if (shares == 0) revert ZeroShares();

        uint256 reclaimAmount = FixedPointMathLib.fullMulDiv(
            shares,
            availableCollateral,
            totalShares
        );

        if (reclaimAmount == 0) revert ZeroReclaimAmount();

        depositor.shares = 0;
        totalShares -= shares;
        availableCollateral -= reclaimAmount;

        collateralAsset.safeTransfer(msg.sender, reclaimAmount);

        emit CollateralReclaimed(msg.sender, shares, reclaimAmount);
    }

    /// @dev Returns the amount of collateral that can be reclaimed by an
    ///      account. This is the portion of the account's deposited collateral
    ///      that has not been liquidated or withdrawn.
    function getReclaimableAmount(
        address _account
    ) public view returns (uint256) {
        uint256 shares = sharesOf(_account);
        if (shares == 0) return 0;
        uint256 reclaimAmount = FixedPointMathLib.fullMulDiv(
            shares,
            availableCollateral,
            totalShares
        );

        return reclaimAmount;
    }

    /// @dev Returns `ceil(x / d)`.
    /// Reverts if `d` is zero.
    /// @custom:author Solady (https://github.com/vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol)
    function divUp(uint256 x, uint256 d) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(d) {
                mstore(0x00, 0x65244e4e) // `DivFailed()`.
                revert(0x1c, 0x04)
            }
            z := add(iszero(iszero(mod(x, d))), div(x, d))
        }
    }
}
