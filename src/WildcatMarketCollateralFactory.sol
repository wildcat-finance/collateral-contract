// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import './WildcatMarketCollateral.sol';
import './libraries/LibStoredInitCode.sol';

contract WildcatMarketCollateralFactory {

    struct TmpCollateralParameterStorage {
      address borrower;
      address collateralToken;
      address associatedMarket;
    }


    TransientBytesArray internal constant _tmpCollateralParameters =
      TransientBytesArray.wrap(uint256(keccak256('Transient:TmpCollateralParameterStorage')) - 1);

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

    ///////////////////////////
    // INTERNAL CODE STORAGE //
    ///////////////////////////

    /**
     * @dev Get the temporary market parameters from transient storage.
     */
    function _getTmpCollateralParameters() internal view returns (TmpCollateralParameterStorage memory parameters)
    {
        return abi.decode(_tmpCollateralParameters.read(), (TmpCollateralParameterStorage));
    }

    /**
     * @dev Set the temporary market parameters in transient storage.
     */
    function _setTmpCollateralParameters(TmpCollateralParameterStorage memory parameters) internal {
        _tmpCollateralParameters.write(abi.encode(parameters));
    }


    function deployCollateralContract(
        address _collateralToken, // this is the choice of collateral, not the underlying of the market
        address _associatedMarket,
        bytes32 salt
    ) public onlyMarketOwner(associatedMarket) returns (address collateralContract) {

    // TODO: feed collateralToken and associatedMarket into the top level of the contract so they
    //        can be fished out in the same way that markets grabbed their parameters in V1.
    //        Is there a smarter way to do this?

    collateralContract = LibStoredInitCode.calculateCreate2Address(ownCreate2Prefix, salt, collateralInitCodeHash);

    TmpCollateralParameterStorage memory tmp = TmpCollateralParameterStorage({
      borrower: msg.sender,
      collateralToken: _collateralToken,
      associatedMarket: _associatedMarket
    });

    _setTmpCollateralParameters(tmp);

    if (collateralContract.code.length != 0) {
      revert CollateralContractAlreadyExists();
    }

    LibStoredInitCode.create2WithStoredInitCode(collateralInitCodeStorage, salt);

    _tmpMarketParameters.setEmpty();


    }
}
