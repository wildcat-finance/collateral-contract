// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import "forge-std/Script.sol";
import {LibStoredInitCode} from "../src/libraries/LibStoredInitCode.sol";
import {WildcatMarketCollateralFactory} from "../src/WildcatMarketCollateralFactory.sol";
import {SimpleMarketCollateralMultiParty} from "../src/SimpleMarketCollateralMultiParty.sol";

contract DeployCollateralFactory is Script {
  function run() external {

    address archController = vm.envAddress("ARCH_CONTROLLER");
    uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));

    address[] memory initialExecutors = vm.envOr("INITIAL_EXECUTORS", ",", new address[](0));
    address[] memory initialExchanges = vm.envOr("INITIAL_EXCHANGES", ",", new address[](0));

    if (pk != 0) {
      vm.startBroadcast(pk);
    } else {
      vm.startBroadcast();
    }

    bytes memory initCode = type(SimpleMarketCollateralMultiParty).creationCode;

    address initCodeStorage = LibStoredInitCode.deployInitCode(initCode);
    uint256 initCodeHash = uint256(keccak256(initCode));

    WildcatMarketCollateralFactory factory = new WildcatMarketCollateralFactory(
      archController,
      initCodeStorage,
      initCodeHash,
      initialExchanges,
      initialExecutors
    );

    vm.stopBroadcast();

    console2.log("ArchController      ", archController);
    console2.log("InitCode storage    ", initCodeStorage);
    console2.log("InitCode hash       ", initCodeHash);
    console2.log("Factory deployed    ", address(factory));
  }
}
