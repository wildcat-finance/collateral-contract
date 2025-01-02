// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import "forge-std/Test.sol";
import '../src/WildcatMarketCollateralFactory.sol';
import '../src/WildcatMarketCollateral.sol';

// Used to grab the init code storage and hash for the factory constructor
contract MockMarketCollateral is WildcatMarketCollateral {}

//contract MockUnderlyingAsset is MockERC20 {}

contract WildcatMarketCollateralFactoryTest is Test {

  WildcatMarketCollateralFactory mockFactory;
  
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
    mockFactory = new WildcatMarketCollateralFactory(initCS, initCH);
  }

}

