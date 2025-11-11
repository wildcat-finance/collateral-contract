// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import "./BaseTest.sol";
import "v2-protocol/libraries/MarketState.sol";

using MathUtils for uint256;

contract SimpleMarketCollateralMultiPartyTest is BaseTest {
    /* -------------------------------------------------------------------------- */
    /*                              Approve Executors                             */
    /* -------------------------------------------------------------------------- */

    function test_approveExecutor() external {
        vm.expectEmit(address(factory));
        emit WildcatMarketCollateralFactory.ExecutorApproved(address(this));
        factory.approveExecutor(address(this));
        assertEq(factory.isApprovedExecutor(address(this)), true);
    }

    function test_approveExecutor_CallerNotArchControllerOwner() external {
        vm.prank(address(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                WildcatMarketCollateralFactory
                    .CallerNotArchControllerOwner
                    .selector
            )
        );
        factory.approveExecutor(address(1));
    }

    function test_removeExecutor() external {
        factory.approveExecutor(address(this));
        vm.expectEmit(address(factory));
        emit WildcatMarketCollateralFactory.ExecutorRemoved(address(this));
        factory.removeExecutor(address(this));
        assertEq(factory.isApprovedExecutor(address(this)), false);
    }

    function test_removeExecutor_CallerNotArchControllerOwner() external {
        vm.prank(address(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                WildcatMarketCollateralFactory
                    .CallerNotArchControllerOwner
                    .selector
            )
        );
        factory.removeExecutor(address(1));
    }

    /* -------------------------------------------------------------------------- */
    /*                             Collateral Contract                            */
    /* -------------------------------------------------------------------------- */

    function test_deposit() external {
        _deposit(100 ether);
        assertEq(collateral.sharesOf(address(this)), 100 ether);
        assertEq(collateral.totalShares(), 100 ether);
        assertEq(collateral.getReclaimableAmount(address(this)), 100 ether);
    }

    function test_deposit_MarketTerminated() external {
        market.setState(100 ether, 100 ether, false, 0, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.MarketTerminated.selector
            )
        );
        collateral.deposit(100 ether);
    }

    function test_deposit_ZeroDepositAmount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.ZeroDepositAmount.selector
            )
        );
        collateral.deposit(0);
    }

    /* -------------------------------------------------------------------------- */
    /*                         getMarketDelinquencyStatus                         */
    /* -------------------------------------------------------------------------- */

    function test_getMarketDelinquencyStatus_MarketTerminated() external {
        market.setState(100 ether, 100 ether, false, 0, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.MarketTerminated.selector
            )
        );
        collateral.getMarketDelinquencyStatus();
    }

    function test_getMarketDelinquencyStatus_DelinquentBeforePenalty()
        external
    {
        market.setState(110 ether, 100 ether, true, 0, false);
        (bool marketInPenalty, uint256 delinquentDebt) = collateral
            .getMarketDelinquencyStatus();
        assertEq(marketInPenalty, false, "Market should not be in penalty");
        assertEq(delinquentDebt, 10 ether, "Delinquent debt should be 10");
    }

    function test_getMarketDelinquencyStatus_Penalty() external {
        market.setState(
            110 ether,
            100 ether,
            true,
            uint32(market.delinquencyGracePeriod()) + 1,
            false
        );
        (bool marketInPenalty, uint256 delinquentDebt) = collateral
            .getMarketDelinquencyStatus();
        assertEq(marketInPenalty, true, "Market should be in penalty");
        assertEq(delinquentDebt, 10 ether, "Delinquent debt should be 10");
    }

    function test_getMarketDelinquencyStatus_NotDelinquent() external {
        market.setState(100 ether, 100 ether, false, 0, false);
        (bool marketInPenalty, uint256 delinquentDebt) = collateral
            .getMarketDelinquencyStatus();
        assertEq(marketInPenalty, false, "Market should not be in penalty");
        assertEq(delinquentDebt, 0, "Delinquent debt should be 0");
    }

    /* -------------------------------------------------------------------------- */
    /*                                Liquidations                                */
    /* -------------------------------------------------------------------------- */

    function test_liquidateCollateral_CallerNotApprovedExecutor() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty
                    .CallerNotApprovedExecutor
                    .selector
            )
        );
        collateral.liquidateCollateral("", 0, 0, 0);
    }

    function test_liquidateCollateral_MarketNotInPenalty() external {
        _updateDelinquency(0, false, false);
        // Market not in penalty causes revert
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.MarketNotInPenalty.selector
            )
        );
        collateral.liquidateCollateral("", 0, 0, 0);
        // Market in penalty but delinquent debt is 0 causes revert
        _updateDelinquency(0, true, false);
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.MarketNotInPenalty.selector
            )
        );
        collateral.liquidateCollateral("", 0, 0, 0);
    }

    function test_liquidateCollateral_MarketTerminated() external {
        market.setState(101 ether, 100 ether, true, 0, true);
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.MarketTerminated.selector
            )
        );
        collateral.liquidateCollateral("", 0, 0, 0);
    }

    function test_liquidateCollateral_InsufficientSwapOutput() external {
        _deposit(100 ether);
        _updateDelinquency(10 ether, true, true);
        bytes memory data = _encodeExecute({
            amountIn: 10 ether,
            amountOut: 10 ether,
            shouldRevert: false
        });
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.InsufficientSwapOutput.selector
            )
        );
        collateral.liquidateCollateral({
            quoteCalldata: data,
            minUnderlyingOut: 11 ether,
            maxCollateralToLiquidate: 10 ether,
            lengthWithdrawalQueue: 0
        });
    }

    function test_liquidateCollateral_BebopSwapFailed() external {
        _deposit(100 ether);
        _updateDelinquency(10 ether, true, true);
        bytes memory data = _encodeExecute({
            amountIn: 10 ether,
            amountOut: 10 ether,
            shouldRevert: true
        });
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.BebopSwapFailed.selector,
                hex""
            )
        );
        collateral.liquidateCollateral({
            quoteCalldata: data,
            minUnderlyingOut: 11 ether,
            maxCollateralToLiquidate: 10 ether,
            lengthWithdrawalQueue: 0
        });
    }

    function test_liquidateCollateral_MaxRepaymentExceeded() external {
        _deposit(100 ether);
        _updateDelinquency(10 ether, true, true);
        bytes memory data = _encodeExecute({
            amountIn: 10 ether,
            amountOut: 11 ether,
            shouldRevert: false
        });
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.MaxRepaymentExceeded.selector
            )
        );
        collateral.liquidateCollateral({
            quoteCalldata: data,
            minUnderlyingOut: 10 ether,
            maxCollateralToLiquidate: 10 ether,
            lengthWithdrawalQueue: 0
        });
    }

    function test_liquidateCollateral() external {
        _deposit(100 ether);
        bytes memory data = _encodeExecute({
            amountIn: 100 ether,
            amountOut: 101 ether,
            shouldRevert: false
        });
        _updateDelinquency(100 ether, true, true);
        vm.prank(executor);

        vm.expectEmit(address(collateralAsset));
        emit ERC20.Approval(address(collateral), bebop, 100 ether);

        vm.expectEmit(address(collateralAsset));
        emit ERC20.Transfer(address(collateral), bebop, 100 ether);

        vm.expectEmit(address(underlyingAsset));
        emit ERC20.Transfer(address(0), address(collateral), 101 ether);

        vm.expectEmit(address(collateralAsset));
        emit ERC20.Approval(address(collateral), bebop, 0);

        vm.expectEmit(address(underlyingAsset));
        emit ERC20.Transfer(address(collateral), address(market), 101 ether);

        vm.expectEmit(address(market));
        emit MockWildcatMarket.Repayment(0, 1);

        vm.expectEmit(address(collateral));
        emit SimpleMarketCollateralMultiParty.Liquidation(
            executor,
            100 ether,
            101 ether
        );
        collateral.liquidateCollateral({
            quoteCalldata: data,
            minUnderlyingOut: 101 ether,
            maxCollateralToLiquidate: 100 ether,
            lengthWithdrawalQueue: 1
        });

        assertEq(
            collateral.nextLiquidationTrigger(),
            block.timestamp + liquidationCooldown
        );
        assertEq(
            collateral.getReclaimableAmount(address(this)),
            0,
            "Reclaim amount should be 0"
        );
        assertEq(
            collateral.sharesOf(address(this)),
            0,
            "Shares should be burned if collateral contract is fully liquidated"
        );
    }

    function test_liquidateCollateral_LiquidationInCooldown() external {
        _deposit(100 ether);
        _fullLiquidation({
            delinquentAmount: 50 ether,
            collateralApproved: 50 ether,
            collateralSpent: 50 ether,
            minUnderlyingOut: 50 ether,
            underlyingReceived: 50 ether
        });
        _updateDelinquency(10 ether, true, true);
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.LiquidationInCooldown.selector
            )
        );
        collateral.liquidateCollateral("", 0, 0, 0);
    }

    function test_liquidateCollateral_Underflow() external {
        _deposit(100 ether);

        // https://dashboard.tenderly.co/kethic/project/tx/0xae4bec560a9f0ccc23b26704e1dcc93471caecdc96279f241fa1bd0b7e23910d
        uint256 totalAssetsBefore = 1_000_000_000_000_000_000;
        MarketState memory traceState = MarketState({
            isClosed: false,
            maxTotalSupply: 2_000_000_000_000_000_000_000_000,
            accruedProtocolFees: 3_890_577_957_511_165,
            normalizedUnclaimedWithdrawals: 6_939_332_798_702_776_300,
            scaledTotalSupply: 98_995_825_804_078_239_729,
            scaledPendingWithdrawals: 48_997_892_878_178_946_646,
            pendingWithdrawalExpiry: 0,
            isDelinquent: true,
            timeDelinquent: uint32(liquidationCooldown + 1),
            protocolFeeBips: 500,
            annualInterestBips: 500,
            reserveRatioBips: 0,
            scaleFactor: 1e27,
            lastInterestAccruedTimestamp: uint32(block.timestamp)
        });

        market.setState(traceState);
        market.setPendingAccruals(
            6_939_332_798_702_776_300,
            3_890_577_957_511_165
        );
        uint256 currentBalance = underlyingAsset.balanceOf(address(market));
        if (currentBalance > 0) {
            underlyingAsset.burn(address(market), currentBalance);
        }
        underlyingAsset.mint(address(market), totalAssetsBefore);

        vm.expectRevert(stdError.arithmeticError);
        market.repayAndProcessUnpaidWithdrawalBatches(0, 1);

        bytes memory data =
            _encodeExecute({amountIn: 6 ether, amountOut: 5_939_340_000_000_000_000, shouldRevert: false});

        // vm.expectRevert(stdError.arithmeticError);
        vm.prank(executor);
        collateral.liquidateCollateral({
            quoteCalldata: data,
            minUnderlyingOut: 5_939_340_000_000_000_000,
            maxCollateralToLiquidate: 6 ether,
            lengthWithdrawalQueue: 1
        });
    }

    function test_liquidateCollateral_NonAtomicPath() external {
        _deposit(100 ether);

        uint256 totalAssetsBefore = 6_939_340_000_000_000_000;
        MarketState memory traceState = MarketState({
            isClosed: false,
            maxTotalSupply: 2_000_000_000_000_000_000_000_000,
            accruedProtocolFees: 3_890_577_957_511_165,
            normalizedUnclaimedWithdrawals: 6_939_332_798_702_776_300,
            scaledTotalSupply: 98_995_825_804_078_239_729,
            scaledPendingWithdrawals: 48_997_892_878_178_946_646,
            pendingWithdrawalExpiry: 0,
            isDelinquent: true,
            timeDelinquent: uint32(liquidationCooldown + 1),
            protocolFeeBips: 500,
            annualInterestBips: 500,
            reserveRatioBips: 0,
            scaleFactor: 1e27,
            lastInterestAccruedTimestamp: uint32(block.timestamp)
        });

        market.setState(traceState);
        market.setPendingAccruals(
            6_939_332_798_702_776_300,
            3_890_577_957_511_165
        );

        uint256 currentBalance = underlyingAsset.balanceOf(address(market));
        if (currentBalance > 0) {
            underlyingAsset.burn(address(market), currentBalance);
        }
        underlyingAsset.mint(address(market), totalAssetsBefore);

        bytes memory data =
            _encodeExecute({amountIn: 6 ether, amountOut: 6_939_340_000_000_000_000, shouldRevert: false});

        vm.prank(executor);
        vm.expectRevert(stdError.arithmeticError);
        collateral.liquidateCollateral({
            quoteCalldata: data,
            minUnderlyingOut: 6_939_340_000_000_000_000,
            maxCollateralToLiquidate: 6 ether,
            lengthWithdrawalQueue: 1
        });
    }

    /// Test that deposits are not penalized for prior liquidations
    function test_depositAfterLiquidation() external {
        _deposit(100 ether);
        console.log("Step 1");
        _fullLiquidation({
            delinquentAmount: 100 ether,
            collateralApproved: 100 ether,
            collateralSpent: 50 ether,
            minUnderlyingOut: 50 ether,
            underlyingReceived: 51 ether
        });
        console.log("Step 2");
        assertApproxEqMinus(
            collateral.getReclaimableAmount(address(this)),
            50 ether,
            1,
            "Reclaim amount should be 50 =/- 1 wei"
        );
        _deposit(50 ether);
        console.log("Step 3");
        assertApproxEqMinus(
            collateral.getReclaimableAmount(address(this)),
            100 ether,
            1,
            "Reclaim amount should be 100 =/- 1 wei"
        );
        fastForward(liquidationCooldown);
        _fullLiquidation({
            delinquentAmount: 10 ether,
            collateralApproved: 10 ether,
            collateralSpent: 10 ether,
            minUnderlyingOut: 10 ether,
            underlyingReceived: 10 ether,
            skipChecks: true
        });
        console.log("Step 4");
        assertApproxEqMinus(
            collateral.getReclaimableAmount(address(this)),
            90 ether,
            1,
            "Reclaim amount should be 90 =/- 1 wei"
        );
        _deposit(address(2), 15 ether);
        console.log("Step 5");
        assertApproxEqMinus(
            collateral.getReclaimableAmount(address(2)),
            15 ether,
            1,
            "Reclaim amount should be 15 =/- 1 wei"
        );
        assertApproxEqMinus(
            collateral.getReclaimableAmount(address(this)),
            90 ether,
            1,
            "Reclaim amount should be 90 =/- 1 wei"
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                              reclaimCollateral                             */
    /* -------------------------------------------------------------------------- */

    function test_reclaimCollateral_MarketNotTerminated() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.MarketNotTerminated.selector
            )
        );
        collateral.reclaimCollateral();
    }

    function test_reclaimCollateral_ZeroShares() external {
        market.setState(0, 0, false, 0, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.ZeroShares.selector
            )
        );
        collateral.reclaimCollateral();
    }

    function test_reclaimCollateral_ZeroReclaimAmount_AllCollateralLiquidated()
        external
    {
        _deposit(100 ether);
        _fullLiquidation({
            delinquentAmount: 100 ether,
            collateralApproved: 100 ether,
            collateralSpent: 100 ether,
            minUnderlyingOut: 100 ether,
            underlyingReceived: 100 ether
        });
        market.setState(0, 0, false, 0, true);
        _reclaim(address(this), 0, 100 ether, 0);
    }

    function test_reclaimCollateral_ZeroReclaimAmount_AlreadyReclaimed()
        external
    {
        _deposit(100 ether);
        market.setState(0, 0, false, 0, true);
        _reclaim(address(this), 100 ether, 0, 100 ether);
        _reclaim(address(this), 0, 0, 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                                rescueTokens                                */
    /* -------------------------------------------------------------------------- */

    function test_rescueTokens_CollateralAsset_NoExcessBalance() external {
        _deposit(100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.ZeroTokenBalance.selector
            )
        );
        collateral.rescueTokens(address(collateralAsset));
    }

    function test_rescueTokens_CollateralAsset() external {
        _deposit(100 ether);
        collateralAsset.mint(address(collateral), 1 ether);
        assertEq(
            collateral.availableCollateral(),
            100 ether,
            "availableCollateral"
        );
        vm.expectEmit(address(collateralAsset));
        emit ERC20.Transfer(address(collateral), address(this), 1 ether);
        collateral.rescueTokens(address(collateralAsset));

        _fullLiquidation({
            delinquentAmount: 10 ether,
            collateralApproved: 10 ether,
            collateralSpent: 10 ether,
            minUnderlyingOut: 10 ether,
            underlyingReceived: 10 ether
        });
        collateralAsset.mint(address(collateral), 1 ether);
        assertEq(
            collateral.availableCollateral(),
            90 ether,
            "availableCollateral not updated"
        );

        vm.expectEmit(address(collateralAsset));
        emit ERC20.Transfer(address(collateral), address(this), 1 ether);
        collateral.rescueTokens(address(collateralAsset));
    }

    function test_rescueTokens_UnderlyingAsset_MarketClosed() external {
        _deposit(100 ether);
        market.setState(0, 0, false, 0, true);
        underlyingAsset.mint(address(collateral), 1 ether);
        vm.expectEmit(address(underlyingAsset));
        emit ERC20.Transfer(address(collateral), address(this), 1 ether);
        collateral.rescueTokens(address(underlyingAsset));
    }

    function test_rescueTokens_UnderlyingAsset_CallerNotBorrower() external {
        vm.prank(address(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleMarketCollateralMultiParty.CallerNotBorrower.selector
            )
        );
        collateral.rescueTokens(address(underlyingAsset));
    }

    function test_rescueTokens_UnderlyingAsset_MarketOpen() external {
        _deposit(100 ether);
        underlyingAsset.mint(address(collateral), 1 ether);
        vm.expectEmit(address(underlyingAsset));
        emit ERC20.Transfer(address(collateral), address(market), 1 ether);
        vm.expectEmit(address(market));
        emit MockWildcatMarket.Repayment(0, 0);
        collateral.rescueTokens(address(underlyingAsset));
    }

    function test_violet() external {
        address userA = address(0x0a);
        address userB = address(0x0b);
        address userC = address(0x0c);
        _deposit(userA, 100 ether);
        _fullLiquidation({
            delinquentAmount: 100 ether,
            collateralApproved: 100 ether,
            collateralSpent: 100 ether,
            minUnderlyingOut: 100 ether,
            underlyingReceived: 100 ether
        });
        fastForward(100 days);
        _deposit(userB, 50 ether);
        _fullLiquidation({
            delinquentAmount: 50 ether,
            collateralApproved: 50 ether,
            collateralSpent: 50 ether,
            minUnderlyingOut: 50 ether,
            underlyingReceived: 50 ether
        });
        _deposit(userC, 100 ether);
        assertApproxEqAbs(
            collateral.getReclaimableAmount(userA),
            0,
            1,
            "userA should have 0 reclaimable amount"
        );
        assertApproxEqAbs(
            collateral.getReclaimableAmount(userB),
            0,
            1,
            "userB should have 0 reclaimable amount"
        );
        assertApproxEqAbs(
            collateral.getReclaimableAmount(userC),
            100 ether,
            1,
            "userC should have 100 reclaimable amount"
        );
        // // _deposit(userC, 100 ether);
        // Depositor memory depositorA = collateral.getDepositor(userA);
        // Depositor memory depositorB = collateral.getDepositor(userB);
        // console.log(
        //     "userA liquidation points:",
        //     depositorA.liquidationPointsCorrection
        // );
        // console.log(
        //     "userB liquidation points:",
        //     depositorB.liquidationPointsCorrection
        // );
        // // console.log(
        // //     "userC liquidation points:",
        // //     collateral.liquidationPointsCorrections(userC)
        // // );
        // console.log(
        //     "userA liquidated collateral:",
        //     collateral.getLiquidatedCollateral(userA)
        // );
        // console.log(
        //     "userB liquidated collateral:",
        //     collateral.getLiquidatedCollateral(userB)
        // );
        // console.log(
        //     "userC liquidated collateral:",
        //     collateral.getLiquidatedCollateral(userC)
        // );
        // console.log(
        //     "userA reclaimable amount:",
        //     collateral.getReclaimableAmount(userA)
        // );
        // console.log(
        //     "userB reclaimable amount:",
        //     collateral.getReclaimableAmount(userB)
        // );
        // console.log(
        //     "userC reclaimable amount:",
        //     collateral.getReclaimableAmount(userC)
        // );
        // console.log("total shares:", collateral.totalShares());
        // console.log("total liquidated:", collateral.totalLiquidated());
        // console.log("available collateral:", collateral.availableCollateral());
    }

    function test_invariantResult() external {
        _deposit(
            0x760c0c4C0291fDd86F383Dc81A2E563c2090805A,
            35023802776561736204669
        );
        _fullLiquidation({
            delinquentAmount: 35023802776561736204669,
            collateralApproved: 35023802776561736204669,
            collateralSpent: 35023802776561736204669,
            minUnderlyingOut: 35023802776561736204669,
            underlyingReceived: 35023802776561736204669
        });
        _deposit(0x760c0c4C0291fDd86F383Dc81A2E563c2090805A, 1044352882);
        uint shares = collateral.sharesOf(
            0x760c0c4C0291fDd86F383Dc81A2E563c2090805A
        );
        uint shares2 = collateral
            .getDepositor(0x760c0c4C0291fDd86F383Dc81A2E563c2090805A)
            .shares;
        assertEq(shares, shares2, "shares not updated");
        uint totalShares = collateral.totalShares();
        assertEq(totalShares, shares, "total shares not eq shares");
    }

    function _doLiquidate(
        uint collateralToLiquidate
    ) internal returns (uint256) {
        // delinquentAmount = _hem(delinquentAmount, 1000, type(uint104).max - 100 ether);
        uint availableCollateral = collateral.availableCollateral();
        if (availableCollateral < 1000) {
            return 0;
        }
        collateralToLiquidate = _hem(
            collateralToLiquidate,
            1000,
            availableCollateral
        );
        console.log("available collateral:", availableCollateral);
        console.log("liquidation amount:", collateralToLiquidate);

        _fullLiquidation({
            delinquentAmount: 1 ether,
            collateralApproved: collateralToLiquidate,
            collateralSpent: collateralToLiquidate,
            minUnderlyingOut: 1 ether,
            underlyingReceived: 1 ether
        });
        return collateralToLiquidate;
    }

    function test_violet2() external {
        _deposit(10215);
        uint collateralToLiquidate1 = _doLiquidate(324619612);
        // Depositor memory depositor = collateral.getDepositor(address(this));
        // console.log("shares remaining:", depositor.amountDeposited - depositor.amountLiquidated);

        fastForward(100 days);
        uint collateralToLiquidate2 = _doLiquidate(215013935);
        // console.log("liquidated 1:", collateralToLiquidate1);
        // console.log("liquidated 2:", collateralToLiquidate2);
    }

    /*
    (4444 * type(uint128).max) / 10215
    */

    function _hem(
        uint256 x,
        uint256 min,
        uint256 max
    ) internal pure virtual returns (uint256 result) {
        require(min <= max, "Max is less than min.");
        /// @solidity memory-safe-assembly
        assembly {
            // prettier-ignore
            for {} 1 {} {
                // If `x` is between `min` and `max`, return `x` directly.
                // This is to ensure that dictionary values
                // do not get shifted if the min is nonzero.
                // More info: https://github.com/foundry-rs/forge-std/issues/188
                if iszero(or(lt(x, min), gt(x, max))) {
                    result := x
                    break
                }
                let size := add(sub(max, min), 1)
                if lt(gt(x, 3), gt(size, x)) {
                    result := add(min, x)
                    break
                }
                if lt(lt(x, not(3)), gt(size, not(x))) {
                    result := sub(max, not(x))
                    break
                }
                // Otherwise, wrap x into the range [min, max],
                // i.e. the range is inclusive.
                if iszero(lt(x, max)) {
                    let d := sub(x, max)
                    let r := mod(d, size)
                    if iszero(r) {
                        result := max
                        break
                    }
                    result := sub(add(min, r), 1)
                    break
                }
                let d := sub(min, x)
                let r := mod(d, size)
                if iszero(r) {
                    result := min
                    break
                }
                result := add(sub(max, r), 1)
                break
            }
        }
    }
}
