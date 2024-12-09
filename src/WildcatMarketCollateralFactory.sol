// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import './WildcatMarketCollateral.sol';
import './libraries/LibStoredInitCode.sol';

contract WildcatMarketCollateralFactory {

    uint256 internal immutable ownCreate2Prefix = LibStoredInitCode.getCreate2Prefix(address(this));

    address public immutable collateralInitCodeStorage;
    uint256 public immutable collateralInitCodeHash;

    modifier onlyMarketOwner(address market) {
        if (msg.sender != IWildcatMarket(market).owner()) {
            revert();
        }
        _;
    }

    constructor(
        address _collateralInitCodeStorage,
        uint256 _collateralInitCodeHash
    ) {
        collateralInitCodeStorage = _collateralInitCodeStorage;
        collateralInitCodeHash = _collateralInitCodeHash;
    }

    function deployCollateralContract(
        address collateralToken,
        address associatedMarket,
        bytes32 salt
    ) public onlyMarketOwner(associatedMarket) returns (address collateralContract) {

    // TODO: feed collateralToken and associatedMarket into the top level of the contract so they
    //        can be fished out in the same way that markets grabbed their parameters in V1.
    //        Is there a smarter way to do this?

    collateralContract = LibStoredInitCode.calculateCreate2Address(ownCreate2Prefix, salt, collateralInitCodeHash);

    }
}
