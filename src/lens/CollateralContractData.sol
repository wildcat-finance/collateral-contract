// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "./TokenData.sol";
import "../interfaces/IWildcatMarket.sol";
import "../SimpleMarketCollateralMultiParty.sol";
import "../WildcatMarketCollateralFactory.sol";

using MathUtils for uint256;

struct CollateralContractData {
    address collateralContract;
    // Basic configuration
    address market;
    address marketBorrower;
    address bebopSettlementContract;
    TokenMetadata underlyingAsset;
    TokenMetadata collateralAsset;
    uint32 liquidationCooldown;
    uint16 maxRepaymentBips;
    // Collateral contract state
    uint32 fullLiquidationIndex;
    uint224 totalShares;
    uint256 availableCollateral;
    uint256 collateralBalance;
    uint32 nextLiquidationTrigger;
    // Relevant market state
    bool isMarketClosed;
    bool isMarketInPenalty;
    uint256 delinquentDebt;
    uint256 maxRepayment;
}

struct CollateralContractDepositorData {
    bool isLiquidator;
    uint256 shares;
    uint256 lastFullLiquidationIndex;
    uint256 balanceCollateralAsset;
    uint256 allowanceCollateralAsset;
}

using CollateralContractDataLib for CollateralContractData global;
using CollateralContractDataLib for CollateralContractDepositorData global;

library CollateralContractDataLib {
    function fill(
        CollateralContractData memory data,
        address _collateralContract
    ) internal view {
        data.collateralContract = _collateralContract;
        SimpleMarketCollateralMultiParty collateral = SimpleMarketCollateralMultiParty(
                _collateralContract
            );
        IWildcatMarket market = IWildcatMarket(collateral.market());
        data.market = address(market);
        data.marketBorrower = collateral.marketBorrower();
        data.underlyingAsset.fill(collateral.underlyingAsset());
        data.collateralAsset.fill(collateral.collateralAsset());
        data.liquidationCooldown = collateral.LIQUIDATION_COOLDOWN();
        data.maxRepaymentBips = collateral.maxRepaymentBips();

        data.fullLiquidationIndex = collateral.fullLiquidationIndex();
        data.totalShares = collateral.totalShares();
        data.availableCollateral = collateral.availableCollateral();
        data.collateralBalance = IERC20(data.collateralAsset.token).balanceOf(
            _collateralContract
        );
        data.nextLiquidationTrigger = collateral.nextLiquidationTrigger();

        MarketState memory state = market.currentState();
        data.isMarketClosed = state.isClosed;
        data.isMarketInPenalty =
            state.timeDelinquent > data.liquidationCooldown;
        uint256 coverageLiquidity = state.liquidityRequired();
        uint256 marketTotalAssets = IERC20(data.underlyingAsset.token)
            .balanceOf(address(market));

        data.delinquentDebt = coverageLiquidity.satSub(marketTotalAssets);
        data.maxRepayment = data.delinquentDebt.bipMul(data.maxRepaymentBips);
    }

    function fill(
        CollateralContractDepositorData memory data,
        CollateralContractData memory collateralData,
        WildcatMarketCollateralFactory factory,
        address _depositor
    ) internal view {
        SimpleMarketCollateralMultiParty collateral = SimpleMarketCollateralMultiParty(
                collateralData.collateralContract
            );
        Depositor memory depositor = collateral.getDepositor(_depositor);
        data.isLiquidator = factory.isApprovedExecutor(_depositor);
        data.shares = depositor.shares;
        data.lastFullLiquidationIndex = depositor.lastFullLiquidationIndex;
        data.balanceCollateralAsset = IERC20(
            collateralData.collateralAsset.token
        ).balanceOf(_depositor);
        data.allowanceCollateralAsset = IERC20(
            collateralData.collateralAsset.token
        ).allowance(_depositor, collateralData.collateralContract);
    }
}
