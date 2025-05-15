// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import "./BaseTest.sol";

using MathUtils for uint256;

contract CollateralHandler {
    SimpleMarketCollateralMultiParty collateral;
    MockERC20 collateralAsset;
    MockWildcatMarket market;
    address executor;
    Vm private vm;
    BaseTest test;
    uint public ghost_zeroLiquidations;

    mapping(bytes32 => uint256) public calls;

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("-------------------");
        console.log("deposit", calls["deposit"]);
        console.log("liquidateCollateral", calls["liquidateCollateral"]);
        console.log("reclaimCollateral", calls["reclaimCollateral"]);
        console.log("fullLiquidate", calls["fullLiquidate"]);
        console.log("-------------------");

        console.log("Zero liquidations:", ghost_zeroLiquidations);
    }

    constructor(
        SimpleMarketCollateralMultiParty _collateral,
        MockERC20 _collateralAsset,
        MockWildcatMarket _market,
        address _executor,
        BaseTest _test
    ) {
        collateral = _collateral;
        collateralAsset = _collateralAsset;
        market = _market;
        executor = _executor;
        test = _test;
        vm = Vm(
            address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))
        );
    }

    // function closeMarket() public {
    //     market.setState(100 ether, 100 ether, false, 0, true);
    // }

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

    function deposit(
        address depositor,
        uint256 amount
    ) public countCall("deposit") {
        amount = _hem(amount, 1000, type(uint104).max - 100 ether);
        // Mint tokens to depositor
        collateralAsset.mint(depositor, amount);
        // Approve collateral contract to spend tokens
        vm.prank(depositor);
        collateralAsset.approve(address(collateral), amount);
        // Deposit
        vm.prank(depositor);
        collateral.deposit(amount);
        // Update expectations
        test.addDepositor(depositor, amount);
    }

    function fullLiquidate() external countCall("fullLiquidate") {
        uint availableCollateral = collateral.availableCollateral();
        if (availableCollateral == 0) {
            ghost_zeroLiquidations++;
            return;
        }
        liquidateCollateral(
            availableCollateral,
            availableCollateral,
            availableCollateral
        );
    }

    function liquidateCollateral(
        uint256 delinquentAmount,
        uint256 collateralToLiquidate,
        uint256 underlyingOut
    ) public countCall("liquidateCollateral") {
        delinquentAmount = _hem(delinquentAmount, 1000, type(uint104).max - 100 ether);
        if (collateral.nextLiquidationTrigger() > block.timestamp) {
            vm.warp(collateral.nextLiquidationTrigger() + 1);
        }
        uint availableCollateral = collateral.availableCollateral();
        if (availableCollateral < 1000) {
            ghost_zeroLiquidations++;
            return;
        }
        collateralToLiquidate = _hem(
            collateralToLiquidate,
            1000,
            availableCollateral
        );
        underlyingOut = _hem(underlyingOut, 1000, delinquentAmount);

        // Set market state to delinquent
        market.setState(
            100 ether + delinquentAmount,
            100 ether,
            true,
            uint32(market.delinquencyGracePeriod()) + 1,
            false
        );

        // Encode Bebop execute call
        bytes memory data = abi.encodeWithSelector(
            MockBebop.execute.selector,
            address(collateralAsset),
            collateralToLiquidate,
            address(market.asset()),
            underlyingOut,
            false
        );

        // Execute liquidation
        vm.prank(executor);
        collateral.liquidateCollateral({
            quoteCalldata: data,
            minUnderlyingOut: underlyingOut,
            maxCollateralToLiquidate: collateralToLiquidate,
            lengthWithdrawalQueue: 1
        });
        // Update expectations
        test.subtractLiquidatedCollateral(collateralToLiquidate);
    }

    function reclaimCollateral(
        address depositor
    ) public countCall("reclaimCollateral") {
        if (!market.isClosed()) {
            market.setState(100 ether, 100 ether, false, 0, true);
        }
        vm.prank(depositor);
        collateral.reclaimCollateral();
        // Update expectations
        test.updateReclaimedCollateral(depositor);
    }

    function rescueTokens(address token) public countCall("rescueTokens") {
        vm.prank(collateral.marketBorrower());
        collateral.rescueTokens(token);
    }
}

contract SimpleMarketCollateralMultiPartyInvariantTest is BaseTest {
    CollateralHandler handler;

    function setUp() public override {
        super.setUp();

        // Create handler
        handler = new CollateralHandler(
            collateral,
            collateralAsset,
            market,
            executor,
            this
        );

        // Add handler as target

        // Set target selectors
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = CollateralHandler.deposit.selector;
        selectors[1] = CollateralHandler.liquidateCollateral.selector;
        selectors[2] = CollateralHandler.reclaimCollateral.selector;
        // selectors[3] = CollateralHandler.rescueTokens.selector;
        selectors[3] = CollateralHandler.fullLiquidate.selector;
        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
        targetContract(address(handler));
    }

    function invariant_callSummary() public {
        handler.callSummary();
    }

    function invariant_totalDepositedMatchesSum() public {
        uint256 sum = 0;
        for (uint256 i = 0; i < expectations.depositors.length; i++) {
            address depositor = expectations.depositors[i];
            Depositor memory _depositor = collateral.getDepositor(depositor);
            sum += _depositor.shares;
        }
        assertEq(
            sum,
            collateral.totalShares(),
            "Sum of deposits should match total deposited"
        );
        assertEq(
            sum,
            collateral.totalShares(),
            "Sum of deposits should match contract total deposited"
        );
    }

    function invariant_availableCollateralMatches() public {
        assertEq(
            expectations.activeCollateral,
            collateral.availableCollateral(),
            "Available collateral should match expectations"
        );
    }

    function invariant_reclaimableAmounts() public {
        for (uint256 i = 0; i < expectations.depositors.length; i++) {
            address depositor = expectations.depositors[i];
            assertApproxEqAbs(
                collateral.getReclaimableAmount(depositor),
                getShareValue(depositor),
                expectations.maxRoundingError[depositor],
                "Reclaimable amount should match expectations"
            );
        }
    }

    // function invariant_liquidatedCollateralProportional() public {
    //     uint256 totalLiquidated = expectations.totalDeposited - expectations.activeCollateral;
    //     if (totalLiquidated == 0) return;

    //     for (uint256 i = 0; i < expectations.depositors.length; i++) {
    //         address depositor = expectations.depositors[i];
    //         uint256 actual = collateral.getLiquidatedCollateral(depositor);
    //         uint256 expected = expectations.liquidatedAmounts[depositor];
    //         assertGe(
    //             actual,
    //             expected,
    //             "Liquidated collateral should be greater than or equal to expected"
    //         );
    //         assertApproxEqAbs(
    //             actual,
    //             expected,
    //             1,
    //             "Liquidated collateral should be proportional to deposit"
    //         );
    //     }
    // }

    /// INVARIANTS:
    /// 1. No depositor can withdraw more than their deposited amount minus their proportion of
    /// liquidated collateral.
    /// 2. The sum of all withdrawable amounts should be less than or equal to the total available
    /// collateral.
    function invariant_canNotWithdrawMoreThanAvailable() public {
        uint256 totalDeposited = collateral.totalShares();
        if (totalDeposited == 0) return;
        uint256 sumAvailable;
        for (uint256 i = 0; i < expectations.depositors.length; i++) {
            address depositor = expectations.depositors[i];
            uint256 actual = collateral.getReclaimableAmount(depositor);
            uint256 expected = getShareValue(depositor);
            assertLe(
                actual,
                expected,
                "Reclaimable amount should be <= deposited amount minus liquidated collateral"
            );
            assertApproxEqAbs(
                actual,
                expected,
                1,
                "Reclaimable amount should be equal to deposited amount minus liquidated collateral within 1 wei"
            );
            sumAvailable += actual;
        }
        assertLe(
            sumAvailable,
            collateral.availableCollateral(),
            "Sum of reclaimable amounts should be <= available collateral"
        );
        assertLe(
            sumAvailable,
            collateralAsset.balanceOf(address(collateral)),
            "Sum of reclaimable amounts should be <= collateral asset balance"
        );
        assertApproxEqAbs(
            sumAvailable,
            collateral.availableCollateral(),
            expectations.depositors.length,
            "Sum of reclaimable amounts should be equal to available collateral within 1 wei per depositor"
        );
    }

    // function invariant_canAlwaysWithdrawWhenClosed() public {
    //     if (!market.isClosed()) return;
    //     for (uint256 i = 0; i < expectations.depositors.length; i++) {
    //         address depositor = expectations.depositors[i];

    //         assertEq(collateral.getReclaimableAmount(depositor), 0, "Reclaimable amount should be 0 when market is closed");
    //     }
    // }
}
