// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import "forge-std/Test.sol";
import '../src/WildcatMarketCollateralFactory.sol';
import '../src/WildcatMarketCollateral.sol';

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

contract MockWildcatMarketTest is IWildcatMarket {}

// Used to grab the init code storage and hash for the factory constructor
contract MockMarketCollateral is WildcatMarketCollateral {}

contract WildcatMarketCollateralFactoryTest is Test {

  WildcatMarketCollateralFactory mockFactory;
  MockERC20 mockUnderlying;
  
  address admin = address(0x01);

  function _storeCollateralInitCode()
    internal
    returns (address initCodeStorage, uint256 initCodeHash)
  {
    bytes memory collateralInitCode = type(MockMarketCollateral).creationCode;
    initCodeHash = uint256(keccak256(collateralInitCode));
    initCodeStorage = LibStoredInitCode.deployInitCode(collateralInitCode);
  }

  function setUp() public {
    (address initCS, uint initCH) = _storeCollateralInitCode();
    mockUnderlying = new MockERC20('Token', 'TKN', 18);

    // TODO: generate a new market
    mockFactory = new WildcatMarketCollateralFactory(initCS, initCH);
  }

  function test_blah() public {
    assertTrue(true);
  }

}

