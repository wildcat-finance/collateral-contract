// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import "forge-std/Script.sol";

interface ICollateralFactory {
  function deployCollateralContract(address collateralToken, address market) external returns (address);
  function collateralInitCodeHash() external view returns (uint256);
}

contract DeployCollateralForMarket is Script {
  function run() external {
    // Expected env:
    // FACTORY: address of WildcatMarketCollateralFactory
    // MARKET: address of the Wildcat market to collateralize
    // COLLATERAL_TOKEN: ERC20 collateral token address
    // PRIVATE_KEY: sender key (or use --private-key flag)

    address factory = vm.envAddress("FACTORY");
    address market = vm.envAddress("MARKET");
    address collateralToken = vm.envAddress("COLLATERAL_TOKEN");

    uint256 pk = vm.envUint("PRIVATE_KEY");

    vm.startBroadcast(pk);

    // Deploy (reverts if a collateral already exists for this token/market pair)
    address deployed = ICollateralFactory(factory).deployCollateralContract(collateralToken, market);

    vm.stopBroadcast();

    // Log details
    uint256 initCodeHash = ICollateralFactory(factory).collateralInitCodeHash();
    console2.log("Factory           ", factory);
    console2.log("Market            ", market);
    console2.log("Collateral token  ", collateralToken);
    console2.log("Collateral deployed", deployed);
    console2.log("Init code hash    ", initCodeHash);
  }
}
