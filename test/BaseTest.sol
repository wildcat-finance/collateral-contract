// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import "forge-std/Test.sol";
import "../src/WildcatMarketCollateralFactory.sol";
import {WildcatMarketCollateralFactory, LibStoredInitCode, SimpleMarketCollateralMultiParty} from "src/WildcatMarketCollateralFactory.sol";
import "v2-protocol/libraries/MathUtils.sol";
import "solady/tokens/ERC20.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {fastForward} from "./utils/Time.sol";

import {MockWildcatMarket} from "./mocks/MockWildcatMarket.sol";
import {MockWildcatArchController} from "./mocks/MockWildcatArchController.sol";
import {MockBebop} from "./mocks/MockBebop.sol";
import "solady/utils/FixedPointMathLib.sol";

using MathUtils for uint256;

struct CollateralExpectations {
    address[] depositors;
    mapping(address => uint256) depositAmounts;
    mapping(address => uint256) liquidatedAmounts;
    // Increase by 1 each time a liquidation is performed
    mapping(address => uint256) maxRoundingError;
    uint256 totalDeposited;
    uint256 activeCollateral;
}

contract BaseTest is Test {
    MockWildcatArchController archController;
    WildcatMarketCollateralFactory factory;
    MockWildcatMarket market;
    MockERC20 underlyingAsset;
    MockERC20 collateralAsset;
    address bebop = 0xbbbbbBB520d69a9775E85b458C58c648259FAD5F;
    SimpleMarketCollateralMultiParty collateral;
    address executor = address(1);
    uint liquidationCooldown;
    CollateralExpectations public expectations;

    function addDepositor(address depositor, uint256 depositAmount) public {
        if (
            expectations.depositAmounts[depositor] == 0 &&
            expectations.liquidatedAmounts[depositor] == 0
        ) {
            expectations.depositors.push(depositor);
        }
        expectations.depositAmounts[depositor] += depositAmount;
        expectations.totalDeposited += depositAmount;
        expectations.activeCollateral += depositAmount;
    }

    function subtractLiquidatedCollateral(uint256 liquidatedCollateral) public {
        for (uint256 i = 0; i < expectations.depositors.length; i++) {
            address depositor = expectations.depositors[i];
            uint256 depositAmount = expectations.depositAmounts[depositor];
            if (depositAmount > 0) {
                uint256 proportionalShare = FixedPointMathLib.mulDivUp(
                    liquidatedCollateral,
                    depositAmount,
                    expectations.activeCollateral
                );
                expectations.depositAmounts[depositor] = expectations
                    .depositAmounts[depositor]
                    .satSub(proportionalShare);
                expectations.liquidatedAmounts[depositor] += proportionalShare;
                expectations.maxRoundingError[depositor] += 1;
            }
        }
        expectations.activeCollateral = expectations.activeCollateral.satSub(
            liquidatedCollateral
        );
    }

    function updateReclaimedCollateral(address depositor) public {
        expectations.depositAmounts[depositor] = 0;
        expectations.activeCollateral -= expectations.depositAmounts[depositor];
    }

    function validateCollateralExpectations() internal view {
        assertEq(
            expectations.totalDeposited,
            collateral.totalDeposited(),
            "totalDeposited mismatch"
        );
        assertEq(
            expectations.activeCollateral,
            collateral.availableCollateral(),
            "activeCollateral mismatch"
        );
        for (uint256 i = 0; i < expectations.depositors.length; i++) {
            address depositor = expectations.depositors[i];
            assertApproxEqAbs(
                expectations.depositAmounts[depositor],
                collateral.getReclaimableAmount(depositor),
                expectations.maxRoundingError[depositor],
                "depositAmount mismatch"
            );
        }
    }

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

    function setUp() public virtual {
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

    function _deposit(
        address account,
        uint256 amount
    )
        internal
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
        addDepositor(account, amount);

        assertEq(collateral.totalShares(), totalShares + amount);
        assertEq(collateral.totalDeposited(), totalDeposited + amount);
        assertEq(
            collateral.availableCollateral(),
            availableCollateral + amount,
            "availableCollateral not updated"
        );
        validateCollateralExpectations();
    }

    function _deposit(uint256 amount) internal {
        _deposit(address(this), amount);
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
        subtractLiquidatedCollateral(collateralSpent);
        validateCollateralExpectations();
    }

    struct StaticValues {
        uint totalLiquidated;
        uint totalDeposited;
        uint liquidatedCollateral;
        uint liquidationPointsCorrections;
    }

    function _reclaim(
        address account,
        uint256 shares,
        uint256 _liquidatedCollateral,
        uint256 reclaimAmount
    )
        internal
    {
        StaticValues memory staticValues;
        staticValues.totalLiquidated = collateral.totalLiquidated();
        staticValues.totalDeposited = collateral.totalDeposited();
        staticValues.liquidatedCollateral = collateral.getLiquidatedCollateral(
            account
        );
        staticValues.liquidationPointsCorrections = collateral
            .liquidationPointsCorrections(account);

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
        assertEq(
            collateral.totalLiquidated(),
            staticValues.totalLiquidated,
            "totalLiquidated changed"
        );
        assertEq(
            collateral.totalDeposited(),
            staticValues.totalDeposited,
            "totalDeposited changed"
        );
        assertEq(
            collateral.getLiquidatedCollateral(account),
            staticValues.liquidatedCollateral,
            "liquidatedCollateral changed"
        );
        assertEq(
            collateral.liquidationPointsCorrections(account),
            staticValues.liquidationPointsCorrections,
            "liquidationPointsCorrections changed"
        );
    }

    /// @dev Asserts that two values are approximately equal, with the actual value allowed to be greater
    /// than the expected value by a maximum of `delta`
    function assertApproxEqPlus(uint256 actual, uint256 expected, uint256 delta, string memory err) public {
        assertGe(actual, expected, string.concat(err, " actual is less than expected"));
        assertLe(actual, expected + delta, string.concat(err, " actual exceeds expected by more than delta"));
    }

    function assertApproxEqPlus(uint256 actual, uint256 expected, uint256 delta) public {
        assertApproxEqPlus(actual, expected, delta, "");
    }

    /// @dev Asserts that two values are approximately equal, with the actual value allowed to be less
    /// than the expected value by a maximum of `delta`
    function assertApproxEqMinus(uint256 actual, uint256 expected, uint256 delta, string memory err) public {
        assertLe(actual, expected, string.concat(err, " actual is greater than expected"));
        assertGe(actual, expected - delta, string.concat(err, " actual is less than expected by more than delta"));
    }

    function assertApproxEqMinus(uint256 actual, uint256 expected, uint256 delta) public {
        assertApproxEqMinus(actual, expected, delta, "");
    }
}