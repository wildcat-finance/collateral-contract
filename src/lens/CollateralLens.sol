// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CollateralContractData, CollateralContractDepositorData} from "./CollateralContractData.sol";
import "../WildcatMarketCollateralFactory.sol";

contract CollateralLens {
    WildcatMarketCollateralFactory public immutable factory;

    constructor(address _factory) {
        factory = WildcatMarketCollateralFactory(_factory);
    }

    function getCollateralContract(
        address collateralContract
    ) public view returns (CollateralContractData memory data) {
        data.fill(collateralContract);
    }

    function getCollateralContractWithDepositor(
        address collateralContract,
        address depositor
    ) public view returns (CollateralContractData memory data, CollateralContractDepositorData memory depositorData) {
        data.fill(collateralContract);
        depositorData.fill(data, factory, depositor);
    }

    function getCollateralContractsWithDepositor(
        address[] memory collateralContracts,
        address depositor
    ) public view returns (CollateralContractData[] memory data, CollateralContractDepositorData[] memory depositorData) {
        data = new CollateralContractData[](collateralContracts.length);
        depositorData = new CollateralContractDepositorData[](collateralContracts.length);
        for (uint256 i = 0; i < collateralContracts.length; i++) {
            data[i].fill(collateralContracts[i]);
            depositorData[i].fill(data[i], factory, depositor);
        }
    }

    function getCollateralContractsForMarket(
        address market
    ) public view returns (CollateralContractData[] memory data) {
        address[] memory collateralContracts = factory.getCollateralContractsForMarket(market);
        data = new CollateralContractData[](collateralContracts.length);
        for (uint256 i = 0; i < collateralContracts.length; i++) {
            data[i].fill(collateralContracts[i]);
        }
    }

    function getCollateralContractsForMarket(
        address market,
        uint256 start,
        uint256 end 
    ) public view returns (CollateralContractData[] memory data) {
        address[] memory collateralContracts = factory.getCollateralContractsForMarket(market, start, end);
        data = new CollateralContractData[](collateralContracts.length);
        for (uint256 i = 0; i < collateralContracts.length; i++) {
            data[i].fill(collateralContracts[i]);
        }
    }
    
    function getCollateralContractsForMarketWithDepositor(
        address market,
        address depositor
    ) public view returns (CollateralContractData[] memory data, CollateralContractDepositorData[] memory depositorData) {
        address[] memory collateralContracts = factory.getCollateralContractsForMarket(market);
        data = new CollateralContractData[](collateralContracts.length);
        depositorData = new CollateralContractDepositorData[](collateralContracts.length);
        for (uint256 i = 0; i < collateralContracts.length; i++) {
            data[i].fill(collateralContracts[i]);
            depositorData[i].fill(data[i], factory, depositor);
        }
    }
}
