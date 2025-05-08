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

    function deposit(address depositor, uint256 amount) public {
        amount = _hem(amount, 0, type(uint104).max);
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

    function liquidateCollateral(
        uint256 delinquentAmount,
        uint256 collateralToLiquidate,
        uint256 underlyingOut
    ) public {
        delinquentAmount = _hem(delinquentAmount, 0, type(uint104).max);
        collateralToLiquidate = _hem(
            collateralToLiquidate,
            0,
            collateral.availableCollateral()
        );
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

    function reclaimCollateral(address depositor) public {
        vm.prank(depositor);
        collateral.reclaimCollateral();
        // Update expectations
        test.updateReclaimedCollateral(depositor);
    }

    function rescueTokens(address token) public {
        vm.prank(collateral.marketBorrower());
        collateral.rescueTokens(token);
    }
}

contract SimpleMarketCollateralMultiPartyInvariantTest is
    BaseTest
{
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
        targetContract(address(handler));

        // Set target selectors
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = CollateralHandler.deposit.selector;
        selectors[1] = CollateralHandler.liquidateCollateral.selector;
        selectors[2] = CollateralHandler.reclaimCollateral.selector;
        selectors[3] = CollateralHandler.rescueTokens.selector;

        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
    }

    function invariant_totalDepositedMatchesSum() public {
        uint256 sum = 0;
        for (uint256 i = 0; i < expectations.depositors.length; i++) {
            address depositor = expectations.depositors[i];
            (, uint248 amountDeposited) = collateral.getDepositor(depositor);
            sum += amountDeposited;
        }
        assertEq(
            sum,
            expectations.totalDeposited,
            "Sum of deposits should match total deposited"
        );
        assertEq(
            sum,
            collateral.totalDeposited(),
            "Sum of deposits should match contract total deposited"
        );
    }

    function invariant_availableCollateralMatches() public {
        assertEq(
            expectations.activeCollateral,
            collateral.availableCollateral(),
            "Available collateral should match expectations"
        );
        assertEq(
            collateral.totalDeposited() - collateral.totalLiquidated(),
            collateral.availableCollateral(),
            "Available collateral should be total deposited minus liquidated"
        );
    }

    function invariant_reclaimableAmounts() public {
        for (uint256 i = 0; i < expectations.depositors.length; i++) {
            address depositor = expectations.depositors[i];
            assertApproxEqAbs(
                expectations.depositAmounts[depositor],
                collateral.getReclaimableAmount(depositor),
                expectations.maxRoundingError[depositor],
                "Reclaimable amount should match expectations"
            );
        }
    }

    function invariant_totalShares() public {
        assertEq(
            collateral.totalShares(),
            collateral.totalDeposited(),
            "Total shares should equal total deposited"
        );
    }

    function invariant_liquidatedCollateralProportional() public {
        uint256 totalLiquidated = collateral.totalLiquidated();
        if (totalLiquidated == 0) return;

        for (uint256 i = 0; i < expectations.depositors.length; i++) {
            address depositor = expectations.depositors[i];
            uint256 actual = collateral.getLiquidatedCollateral(depositor);
            uint256 expected = expectations.liquidatedAmounts[depositor];
            assertGe(
                actual,
                expected,
                "Liquidated collateral should be greater than or equal to expected"
            );
            assertApproxEqAbs(
                actual,
                expected,
                1,
                "Liquidated collateral should be proportional to deposit"
            );
        }
    }

    /// INVARIANTS:
    /// 1. No depositor can withdraw more than their deposited amount minus their proportion of
    /// liquidated collateral.
    /// 2. The sum of all withdrawable amounts should be less than or equal to the total available
    /// collateral.
    function invariant_canNotWithdrawMoreThanAvailable() public {
        uint256 totalDeposited = collateral.totalDeposited();
        if (totalDeposited == 0) return;
        uint256 sumAvailable;
        for (uint256 i = 0; i < expectations.depositors.length; i++) {
            address depositor = expectations.depositors[i];
            uint256 actual = collateral.getReclaimableAmount(depositor);
            uint256 expected = expectations.depositAmounts[depositor];
            /* assertGe(
                actual,
                expected,
                "Reclaimable amount should be <= deposited amount minus liquidated collateral"
            ); */
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
        assertApproxEqAbs(
            sumAvailable,
            collateral.availableCollateral(),
            expectations.depositors.length,
            "Sum of reclaimable amounts should be equal to available collateral within 1 wei per depositor"
        );
    }
}