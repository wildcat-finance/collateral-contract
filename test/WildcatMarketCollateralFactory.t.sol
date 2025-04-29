// // SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
// pragma solidity >=0.8.20;

// import "forge-std/Test.sol";
// import "../src/WildcatMarketCollateralFactory.sol";
// import {SimpleMarketCollateral} from "src/SimpleMarketCollateral.sol";
// import "v2-protocol/libraries/MarketState.sol";
// import 'solady/tokens/ERC20.sol';

// import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

// contract MockWildcatMarket {
//     MarketState internal _state;

//     address public borrower;
//     address public asset;
//     uint256 public delinquencyGracePeriod;

//     constructor(
//         address _borrower,
//         address _asset,
//         uint256 _delinquencyGracePeriod
//     ) {
//         borrower = _borrower;
//         asset = _asset;
//         delinquencyGracePeriod = _delinquencyGracePeriod;
//     }

//     function currentState() public view returns (MarketState memory) {
//         return _state;
//     }

//     function setState(MarketState memory state) public {
//         _state = state;
//     }

//     function repayAndProcessUnpaidWithdrawalBatches(
//         uint256 repayAmount,
//         uint256 maxBatches
//     ) public {

//     }

//     function isClosed() public view returns (bool) {
//         return _state.isClosed;
//     }
// }

// contract WildcatMarketCollateralFactoryTest is Test {
//     WildcatMarketCollateralFactory mockFactory;
//     MockERC20 mockUnderlying;

//     address admin = address(0x01);

//     function _storeCollateralInitCode()
//         internal
//         returns (address initCodeStorage, uint256 initCodeHash)
//     {
//         bytes memory collateralInitCode = type(MockMarketCollateral)
//             .creationCode;
//         initCodeHash = uint256(keccak256(collateralInitCode));
//         initCodeStorage = LibStoredInitCode.deployInitCode(collateralInitCode);
//     }

//     function setUp() public {
//         (address initCS, uint initCH) = _storeCollateralInitCode();
//         mockUnderlying = new MockERC20("Token", "TKN", 18);

//         // TODO: generate a new market
//         mockFactory = new WildcatMarketCollateralFactory(initCS, initCH);
//     }

//     function test_blah() public {
//         assertTrue(true);
//     }
// }
