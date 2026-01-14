// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import {Script} from "forge-std/Script.sol";
import "./LibDeployment.sol";
import {WildcatMarketCollateralFactory} from "../src/WildcatMarketCollateralFactory.sol";
import {IWildcatArchController} from "v2-protocol/interfaces/IWildcatArchController.sol";

string constant DeploymentsJsonFilePath = "deployments.json";

contract DeployCollateral is Script {
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

    function deployFactory(Deployments memory deployments) internal {
        address _archController;
        if (block.chainid == 1) {
            _archController = deployments.get("WildcatArchController");
        } else {
            bytes memory archControllerCreationCode = _getCreationCode(
                deployments,
                "MockArchController"
            );
            (_archController, ) = deployments.getOrDeploy(
                "MockArchController",
                archControllerCreationCode,
                false
            );
        }
        bytes memory collateralCreationCode = _getCreationCode(
            deployments,
            "SimpleMarketCollateralMultiParty"
        );
        bytes32 collateralInitCodeHash = keccak256(collateralCreationCode);

        (address collateralInitCodeStorage, ) = deployments
            .getOrDeployInitcodeStorage(
                "SimpleMarketCollateralMultiParty",
                collateralCreationCode,
                true
            );
        address[] memory _initialExchanges;
        address[] memory _initialExecutors;

        if (block.chainid == 1) {
            _initialExchanges = new address[](1);
            _initialExchanges[0] = 0xbbbbbBB520d69a9775E85b458C58c648259FAD5F;
            _initialExecutors = new address[](1);
            _initialExecutors[0] = IWildcatArchController(_archController)
                .owner();
        } else {
            bytes memory bebopSettlementContractCreationCode = _getCreationCode(
                deployments,
                "MockBebopSettlementContract"
            );
            (address bebopSettlementContract, ) = deployments.getOrDeploy(
                "MockBebopSettlementContract",
                bebopSettlementContractCreationCode,
                false
            );
            _initialExchanges = new address[](1);
            _initialExchanges[0] = bebopSettlementContract;
            _initialExecutors = new address[](1);
            _initialExecutors[0] = 0xca732651410E915090d7A7D889A1E44eF4575fcE;
        }

        bytes memory factoryCreationCode = _getCreationCode(
            deployments,
            "WildcatMarketCollateralFactory"
        );
        bytes memory factoryConstructorArgs = abi.encode(
            _archController,
            collateralInitCodeStorage,
            collateralInitCodeHash,
            _initialExchanges,
            _initialExecutors
        );

        deployments.getOrDeploy(
            "WildcatMarketCollateralFactory",
            factoryCreationCode,
            factoryConstructorArgs,
            true
        );

        deployments.write();
    }

    function run() public {
        Deployments memory deployments = getDeploymentsForNetwork("mainnet");

        deployFactory(deployments);
    }
}
