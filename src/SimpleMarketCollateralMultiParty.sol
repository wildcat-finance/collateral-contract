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
    bool hasReclaimed;
    uint248 amountDeposited;
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
///         As users make deposits, they are assigned shares equivalent to their deposit amounts.
///         An additional `liquidationPointsCorrection` value is stored for each user to track the
///         amount of collateral that has been liquidated from their deposit. This functions similarly
///         to dividends in other DeFi protocols (e.g. Sushi's MasterChef), except that the dividends
///         are a debit rather than a credit.
///
///         Shares can be withdrawn once the underlying market is terminated, at a rate of one share per
///         underlying token, with the amount of collateral liquidated from a particular user's deposit
///         being subtracted from the share amount. Note that since liquidation points are tracked per-user,
///         shares returned by the `sharesOf` function are not fungible or even guaranteed to be redeemable.
///         Users who deposit after a given liquidation will still receive 1 share per collateral token deposited,
///         but will not be debited for the previous liquidations.
///
///         The `getLiquidatedCollateral` function can be used to query the amount of collateral that has been
///         liquidated from a user's deposit.
///
///         The `getReclaimableAmount` function can be used to query the amount of collateral that can be reclaimed
///         by a user once the market is terminated (assuming no further liquidations occur).
contract SimpleMarketCollateralMultiParty is ReentrancyGuard {
    using LibERC20 for address;
    using FunctionTypeCasts for *;

    uint128 internal constant POINTS_MULTIPLIER = type(uint128).max;

    mapping(address account => uint256 liquidationPointsCorrection)
        public liquidationPointsCorrections;

    // mapping(address account => uint256 shares) public sharesOf;
    mapping(address account => Depositor depositor) internal _depositors;

    /**
     * @dev Returns the active shares of an account. Note that once an account
     *      has withdrawn, this function will return 0 but the `amountDeposited` value
     *      will still be stored in the `_depositors` mapping for post-withdrawal
     *      queries about the account's deposited & liquidated collateral.
     */
    function sharesOf(address account) public view returns (uint256) {
        Depositor memory depositor = _depositors[account];
        if (depositor.hasReclaimed) return 0;
        return depositor.amountDeposited;
    }

    function getDepositor(
        address account
    ) public view returns (bool hasWithdrawn, uint248 amountDeposited) {
        Depositor memory depositor = _depositors[account];
        hasWithdrawn = depositor.hasReclaimed;
        amountDeposited = depositor.amountDeposited;
    }

    uint256 public liquidationPointsPerShare;

    /// @dev The total active (unwithdrawn) shares of the contract.
    uint248 public totalShares;
    /// @dev The total amount of shares that have been withdrawn.
    uint248 public totalWithdrawn;
    /// @dev The total amount of collateral that has been liquidated.
    uint248 public totalLiquidated;

    /// @dev The total amount of collateral that has been deposited over
    ///      the lifetime of the contract.
    function totalDeposited() public view returns (uint248) {
        return totalShares + totalWithdrawn;
    }

    /// @dev Returns the total available collateral of the contract.
    ///      This is calculated in the contract rather than using the ERC20 balance
    ///      to ensure the borrower can rescue collateral tokens sent to the contract
    ///      by mistake.
    function availableCollateral() public view returns (uint248) {
        return totalShares - totalLiquidated;
    }

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

    event CollateralDeposited(address depositor, uint256 amountDeposited);
    event CollateralReclaimed(
        address reclaimant,
        uint256 sharesBurned,
        uint256 liquidatedCollateral,
        uint256 amountReclaimed
    );
    event Liquidation(
        address liquidator,
        uint256 collateralLiquidated,
        uint256 underlyingReceived
    );
    event UnderlyingAssetSentToMarket(uint256 amountSent);
    event TokenRescued(address token, uint256 amountRescued);

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
    error AlreadyReclaimed();
    error ZeroDepositAmount();
    error DivFailed();

    /// When a user makes a deposit, we track the amount of collateral that had already been liquidated as of their deposit
    /// so as to ensure they are not being penalized for collateral liquidations that occurred previously.
    function _correctLiquidationPointsForDeposit(
        address account,
        uint256 depositAmount
    ) internal {
        uint256 liquidationPoints = depositAmount * liquidationPointsPerShare;
        liquidationPointsCorrections[account] += liquidationPoints;
    }

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

    // TODO: Dillon please sanity check this
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
        uint248 amount = _amount.toUint248();
        collateralAsset.safeTransferFrom(msg.sender, address(this), amount);
        _depositors[msg.sender].amountDeposited += amount;
        totalShares += amount;
        _correctLiquidationPointsForDeposit(msg.sender, amount);

        emit CollateralDeposited(msg.sender, amount);
        return true;
    }

    /**
     * @dev Token rescue function for recovering tokens sent to the contract
     *      contract by mistake or otherwise outside of the normal course of
     *      operation.
     *
     *      Only the borrower can rescue tokens from the contract.
     *      The underlying asset can only be rescued if the market is closed; if the market
     *      is open, the underlying asset is transferred to the market.
     *      The collateral asset can never be rescued.
     */
    function rescueTokens(address token) public onlyBorrower nonReentrant {
        // The collateral asset cannot be rescued.
        if (token == collateralAsset) revert BadRescueAttempt(token);

        uint256 tokenBalance = token.balanceOf(address(this));
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

        // Ensure the market is in penalty state and there is no active cooldown
        if (!marketInPenalty || delinquentDebt == 0)
            revert MarketNotInPenalty();
        if (block.timestamp < nextLiquidationTrigger)
            revert LiquidationInCooldown();

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

        /// @dev Update the liquidation points per share to account for the collateral liquidated
        liquidationPointsPerShare +=
            (collateralLiquidated * POINTS_MULTIPLIER) /
            totalShares;
        totalLiquidated += collateralLiquidated.toUint248();
    }

    function reclaimCollateral() public marketClosed {
        Depositor storage account = _depositors[msg.sender];

        if (account.hasReclaimed) revert AlreadyReclaimed();

        uint256 _shares = account.amountDeposited;
        if (_shares == 0) revert ZeroShares();

        uint256 liquidationPoints = (_shares * liquidationPointsPerShare) -
            liquidationPointsCorrections[msg.sender];
        uint256 liquidatedCollateral = divUp(
            liquidationPoints,
            POINTS_MULTIPLIER
        );
        uint256 reclaimAmount = _shares.satSub(liquidatedCollateral);

        if (reclaimAmount == 0) revert ZeroReclaimAmount();

        totalWithdrawn += uint248(_shares);
        account.hasReclaimed = true;
        totalShares -= uint248(_shares);
        collateralAsset.safeTransfer(msg.sender, reclaimAmount);

        emit CollateralReclaimed(
            msg.sender,
            _shares,
            liquidatedCollateral,
            reclaimAmount
        );
    }

    /// @dev Returns the total collateral that has been liquidated from an
    ///      account's deposits. This value is cumulative and is not affected
    ///      by withdrawals.
    function getLiquidatedCollateral(
        address account
    ) public view returns (uint256) {
        uint256 _shares = _depositors[account].amountDeposited;
        if (_shares == 0) return 0;

        uint256 liquidationPoints = (_shares * liquidationPointsPerShare) -
            liquidationPointsCorrections[account];
        return divUp(liquidationPoints, POINTS_MULTIPLIER);
    }

    /// @dev Returns the amount of collateral that can be reclaimed by an
    ///      account. This is the portion of the account's deposited collateral
    ///      that has not been liquidated or withdrawn.
    function getReclaimableAmount(
        address account
    ) public view returns (uint256) {
        Depositor memory depositor = _depositors[account];
        if (depositor.hasReclaimed) return 0;

        uint256 _shares = depositor.amountDeposited;
        if (_shares == 0) return 0;

        uint256 liquidationPoints = (_shares * liquidationPointsPerShare) -
            liquidationPointsCorrections[account];
        uint256 liquidatedCollateral = divUp(
            liquidationPoints,
            POINTS_MULTIPLIER
        );
        return _shares - liquidatedCollateral;
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
