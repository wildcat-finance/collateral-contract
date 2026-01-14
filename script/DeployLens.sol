// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import {Script} from "forge-std/Script.sol";
import "./LibDeployment.sol";

string constant DeploymentsJsonFilePath = "deployments.json";

contract DeployLens is Script {
    function _getCreationCode(
        Deployments memory deployments,
        string memory namePath
    ) internal returns (bytes memory) {
        ContractArtifact memory artifact = parseContractNamePath(namePath);

        string memory jsonPath = LibDeployment.findForgeArtifact(
            artifact,
            deployments.forgeOutDir
        );
        Json memory forgeArtifact = JsonUtil.create(vm.readFile(jsonPath));
        bytes memory creationCode = forgeArtifact.getBytes("bytecode.object");
        return creationCode;
    }

    function run() public {
        Deployments memory deployments = getDeploymentsForNetwork("mainnet");

        bytes memory lensCreationCode = _getCreationCode(
            deployments,
            "lens/CollateralLens.sol:CollateralLens"
        );
        address collateralFactory = deployments.get("WildcatMarketCollateralFactory");
        bytes memory lensConstructorArgs = abi.encode(
            collateralFactory
        );
        deployments.getOrDeploy(
            "CollateralLens",
            lensCreationCode,
            lensConstructorArgs,
            true
        );

        deployments.write();
    }
}
