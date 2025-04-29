// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import "forge-std/Test.sol";
import "../src/WildcatMarketCollateralFactory.sol";
import {WildcatMarketCollateralFactory, LibStoredInitCode, SimpleMarketCollateralMultiParty} from "src/WildcatMarketCollateralFactory.sol";
import "solady/tokens/ERC20.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {fastForward} from "./utils/Time.sol";

import {MockWildcatMarket} from "./mocks/MockWildcatMarket.sol";
import {MockWildcatArchController} from "./mocks/MockWildcatArchController.sol";
import {MockBebop} from "./mocks/MockBebop.sol";

contract SimpleMarketCollateralMultiPartyTest is Test {
    MockWildcatArchController archController;
    WildcatMarketCollateralFactory factory;
    MockWildcatMarket market;
    MockERC20 underlyingAsset;
    MockERC20 collateralAsset;
    address bebop = 0xbbbbbBB520d69a9775E85b458C58c648259FAD5F;
    SimpleMarketCollateralMultiParty collateral;
    address executor = address(1);
    uint liquidationCooldown;

    function _storeInitCode()
        internal
        virtual
        returns (address initCodeStorage, uint256 initCodeHash)
    {
        bytes memory initCode = type(SimpleMarketCollateralMultiParty)
            .creationCode;
        initCodeHash = uint256(keccak256(initCode));
        initCodeStorage = LibStoredInitCode.deployInitCode(initCode);
    }

    function setUp() public {
        archController = new MockWildcatArchController(address(this));
        vm.etch(bebop, type(MockBebop).runtimeCode);
        (address initCodeStorage, uint256 initCodeHash) = _storeInitCode();
        factory = new WildcatMarketCollateralFactory(
            address(archController),
            initCodeStorage,
            initCodeHash
        );
        factory.approveExecutor(executor);
        underlyingAsset = new MockERC20("Token", "TKN", 18);
        market = new MockWildcatMarket(
            address(this),
            address(underlyingAsset),
            1 days
        );
        liquidationCooldown = market.delinquencyGracePeriod();
        collateralAsset = new MockERC20("Collateral", "CLT", 18);
        collateralAsset.mint(address(this), 1000000 ether);
        collateral = SimpleMarketCollateralMultiParty(
            factory.deployCollateralContract(
                address(collateralAsset),
                address(market)
            )
        );
        assertEq(
            collateral.marketBorrower(),
            address(this),
            "Market borrower mismatch"
        );
        assertEq(
            collateral.collateralAsset(),
            address(collateralAsset),
            "Collateral asset mismatch"
        );
        assertEq(
            collateral.underlyingAsset(),
            address(underlyingAsset),
            "Underlying asset mismatch"
        );
        assertEq(
            address(collateral.market()),
            address(market),
            "Market mismatch"
        );
        vm.label(address(collateral), "Collateral");
        vm.label(address(market), "Market");
        vm.label(address(underlyingAsset), "UnderlyingAsset");
        vm.label(address(collateralAsset), "CollateralAsset");
        vm.label(address(bebop), "Bebop");
    }

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

    function _deposit(address account, uint256 amount) internal assertDoesNotChange(
        address(collateral),
        abi.encodeWithSignature("totalLiquidated()"),
        "totalLiquidated"
    )

     {
        uint256 totalShares = collateral.totalShares();
        uint256 totalDeposited = collateral.totalDeposited();
        uint256 availableCollateral = collateral.availableCollateral();

        collateralAsset.mint(account, amount);
        vm.prank(account);
        collateralAsset.approve(address(collateral), amount);
        vm.expectEmit(address(collateralAsset));
        emit ERC20.Transfer(account, address(collateral), amount);
        vm.prank(account);
        collateral.deposit(amount);

        assertEq(collateral.totalShares(), totalShares + amount);
        assertEq(collateral.totalDeposited(), totalDeposited + amount);
        assertEq(
            collateral.availableCollateral(),
            availableCollateral + amount,
            "availableCollateral not updated"
        );
    }

    function _deposit(uint256 amount) internal {
        _deposit(address(this), amount);
    }

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

    function _updateDelinquency(
        uint256 delinquentAmount,
        bool delinquent,
        bool penalty
    ) internal {
        market.setState(
            100 ether + delinquentAmount,
            100 ether,
            delinquent,
            (delinquent && penalty)
                ? uint32(market.delinquencyGracePeriod()) + 1
                : 0,
            false
        );
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

    function _encodeExecute(
        uint256 amountIn,
        uint256 amountOut,
        bool shouldRevert
    ) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MockBebop.execute.selector,
                address(collateralAsset),
                amountIn,
                address(underlyingAsset),
                amountOut,
                shouldRevert
            );
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
            100 ether,
            "Shares should be the same"
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

    function _fullLiquidation(
        uint256 delinquentAmount,
        uint256 collateralApproved,
        uint256 collateralSpent,
        uint256 minUnderlyingOut,
        uint256 underlyingReceived
    ) internal {
        uint256 totalLiquidated = collateral.totalLiquidated();
        uint256 availableCollateral = collateral.availableCollateral();
        bytes memory data = _encodeExecute({
            amountIn: collateralSpent,
            amountOut: underlyingReceived,
            shouldRevert: false
        });
        _updateDelinquency(delinquentAmount, true, true);

        vm.expectEmit(address(collateralAsset));
        emit ERC20.Approval(address(collateral), bebop, collateralApproved);

        vm.expectEmit(address(collateralAsset));
        emit ERC20.Transfer(address(collateral), bebop, collateralSpent);

        vm.expectEmit(address(underlyingAsset));
        emit ERC20.Transfer(
            address(0),
            address(collateral),
            underlyingReceived
        );

        vm.expectEmit(address(collateralAsset));
        emit ERC20.Approval(address(collateral), bebop, 0);

        vm.expectEmit(address(underlyingAsset));
        emit ERC20.Transfer(
            address(collateral),
            address(market),
            underlyingReceived
        );

        vm.expectEmit(address(market));
        emit MockWildcatMarket.Repayment(0, 1);

        vm.expectEmit(address(collateral));
        emit SimpleMarketCollateralMultiParty.Liquidation(
            executor,
            collateralSpent,
            underlyingReceived
        );
        vm.prank(executor);
        collateral.liquidateCollateral({
            quoteCalldata: data,
            minUnderlyingOut: minUnderlyingOut,
            maxCollateralToLiquidate: collateralApproved,
            lengthWithdrawalQueue: 1
        });

        assertEq(
            collateral.totalLiquidated(),
            totalLiquidated + collateralSpent,
            "totalLiquidated"
        );
        assertEq(
            collateral.availableCollateral(),
            availableCollateral - collateralSpent,
            "availableCollateral"
        );
    }

    /// Test that deposits are not penalized for prior liquidations
    function test_depositAfterLiquidation() external {
        _deposit(100 ether);
        _fullLiquidation({
            delinquentAmount: 100 ether,
            collateralApproved: 100 ether,
            collateralSpent: 50 ether,
            minUnderlyingOut: 50 ether,
            underlyingReceived: 51 ether
        });
        assertEq(
            collateral.getReclaimableAmount(address(this)),
            50 ether,
            "Reclaim amount should be 50"
        );
        _deposit(50 ether);
        assertEq(
            collateral.getReclaimableAmount(address(this)),
            100 ether,
            "Reclaim amount should be 100"
        );
        fastForward(liquidationCooldown);
        _fullLiquidation({
            delinquentAmount: 10 ether,
            collateralApproved: 10 ether,
            collateralSpent: 10 ether,
            minUnderlyingOut: 10 ether,
            underlyingReceived: 10 ether
        });
        assertEq(
            collateral.getReclaimableAmount(address(this)),
            90 ether,
            "Reclaim amount should be 90"
        );
        _deposit(address(2), 15 ether);
        assertEq(
            collateral.getReclaimableAmount(address(2)),
            15 ether,
            "Reclaim amount should be 15"
        );
        assertEq(
            collateral.getReclaimableAmount(address(this)),
            90 ether,
            "Reclaim amount should be 90"
        );
        assertEq(
            collateral.getLiquidatedCollateral(address(2)),
            0,
            "Liquidated collateral should be 0 for new depositor"
        );
        assertEq(
            collateral.getLiquidatedCollateral(address(this)),
            60 ether,
            "Liquidated collateral should be 60 for old depositor"
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
        _reclaim(address(this), 100 ether, 100 ether, 0);
    }

    function test_reclaimCollateral_ZeroReclaimAmount_AlreadyReclaimed()
        external
    {
        _deposit(100 ether);
        market.setState(0, 0, false, 0, true);
        _reclaim(address(this), 100 ether, 0, 100 ether);
        _reclaim(address(this), 0, 0, 0);
    }

    modifier assertDoesNotChange(
        address target,
        bytes memory data,
        string memory label
    ) {
        (bool success, bytes memory returnData) = target.call(data);
        _;
        (bool success2, bytes memory returnData2) = target.call(data);
        assertEq(
            success,
            success2,
            string.concat(label, ": call success changed")
        );
        assertEq(
            returnData,
            returnData2,
            string.concat(label, ": returndata changed")
        );
    }

    function _reclaim(
        address account,
        uint256 shares,
        uint256 _liquidatedCollateral,
        uint256 reclaimAmount
    )
        internal
        assertDoesNotChange(
            address(collateral),
            abi.encodeWithSignature("totalLiquidated()"),
            "totalLiquidated"
        )
        assertDoesNotChange(
            address(collateral),
            abi.encodeWithSignature("totalDeposited()"),
            "totalDeposited"
        )
        assertDoesNotChange(
            address(collateral),
            abi.encodeWithSignature("liquidatedCollateral()"),
            "liquidatedCollateral"
        )
        assertDoesNotChange(
            address(collateral),
            abi.encodeWithSignature(
                "liquidationPointsCorrections(address)",
                account
            ),
            "liquidationPointsCorrections"
        )
    {
        uint256 totalShares = collateral.totalShares();
        uint256 liquidatedCollateral = collateral.getLiquidatedCollateral(
            account
        );
        uint256 totalWithdrawn = collateral.totalWithdrawn();
        uint256 availableCollateral = collateral.availableCollateral();
        assertEq(
            liquidatedCollateral,
            _liquidatedCollateral,
            "liquidatedCollateral"
        );
        (bool hasReclaimed, uint248 amountDeposited) = collateral.getDepositor(
            account
        );

        bool willFail = shares == 0 || reclaimAmount == 0 || hasReclaimed;
        if (hasReclaimed) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    SimpleMarketCollateralMultiParty.AlreadyReclaimed.selector
                )
            );
        } else if (shares == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    SimpleMarketCollateralMultiParty.ZeroShares.selector
                )
            );
        } else if (reclaimAmount == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    SimpleMarketCollateralMultiParty.ZeroReclaimAmount.selector
                )
            );
        } else {
            vm.expectEmit(address(collateralAsset));
            emit ERC20.Transfer(address(collateral), account, reclaimAmount);
            vm.expectEmit(address(collateral));
            emit SimpleMarketCollateralMultiParty.CollateralReclaimed(
                account,
                shares,
                liquidatedCollateral,
                reclaimAmount
            );
        }
        vm.prank(account);
        collateral.reclaimCollateral();
        if (!willFail) {
            assertEq(
                collateral.totalShares(),
                totalShares - shares,
                "totalShares not updated"
            );
            assertEq(
                collateral.totalWithdrawn(),
                totalWithdrawn + reclaimAmount,
                "totalWithdrawn changed"
            );
            assertEq(collateral.sharesOf(account), 0, "sharesOf changed");
            assertEq(
                collateral.getReclaimableAmount(account),
                0,
                "getReclaimableAmount not updated"
            );
            assertEq(
                collateral.getLiquidatedCollateral(account),
                liquidatedCollateral,
                "getLiquidatedCollateral changed"
            );
            (bool hasReclaimed2, uint248 amountDeposited2) = collateral
                .getDepositor(account);
            assertEq(
                amountDeposited2,
                amountDeposited,
                "amountDeposited changed"
            );
            assertEq(hasReclaimed2, true, "hasReclaimed not updated");
            assertEq(
                collateral.availableCollateral(),
                availableCollateral - reclaimAmount,
                "availableCollateral not updated"
            );
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                rescueTokens                                */
    /* -------------------------------------------------------------------------- */
}
