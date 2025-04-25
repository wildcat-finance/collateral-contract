// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import "./SimpleMarketCollateralMultiParty.sol";
import "./libraries/LibStoredInitCode.sol";
import {TransientBytesArray} from "./types/TransientBytesArray.sol";
import "./interfaces/IWildcatArchController.sol";
import "./interfaces/IWildcatMarket.sol";

contract WildcatMarketCollateralFactory {
    struct TmpCollateralParameterStorage {
        address borrower;
        address collateralToken;
        address associatedMarket;
    }

    struct CollateralContract {
        address collateralContractAddress;
        address collateralToken;
        address associatedMarket;
    }

    error CollateralContractAlreadyExists();

    event ExecutorApproved(address indexed executor);
    event ExecutorRemoved(address indexed executor);

    error CallerNotArchControllerOwner();

    modifier onlyArchControllerOwner() {
        if (msg.sender != IWildcatArchController(archController).owner()) {
            revert CallerNotArchControllerOwner();
        }
        _;
    }

    TransientBytesArray internal constant _tmpCollateralParameters =
        TransientBytesArray.wrap(
            uint256(keccak256("Transient:TmpCollateralParameterStorage")) - 1
        );

    uint256 internal immutable ownCreate2Prefix =
        LibStoredInitCode.getCreate2Prefix(address(this));

    address public immutable collateralInitCodeStorage;
    uint256 public immutable collateralInitCodeHash;

    address public immutable archController;

    mapping(address => CollateralContract[]) public collateralContractList;

    mapping(address => bool) public isApprovedExecutor;

    function listCollateralMarkets(
        address _market,
        address _asset
    ) public view returns (address[] memory) {
        CollateralContract[] storage contracts = collateralContractList[
            msg.sender
        ];
        uint count = 0;

        for (uint i = 0; i < contracts.length; i++) {
            if (
                contracts[i].associatedMarket == _market &&
                contracts[i].collateralToken == _asset
            ) {
                count++;
            }
        }

        address[] memory result = new address[](count);
        uint index = 0;

        for (uint i = 0; i < contracts.length; i++) {
            if (
                contracts[i].associatedMarket == _market &&
                contracts[i].collateralToken == _asset
            ) {
                result[index] = contracts[i].collateralContractAddress;
                index++;
            }
        }

        return result;
    }

    constructor(
        address _archController,
        address _collateralInitCodeStorage,
        uint256 _collateralInitCodeHash
    ) {
        archController = _archController;
        collateralInitCodeStorage = _collateralInitCodeStorage;
        collateralInitCodeHash = _collateralInitCodeHash;
    }

    function approveExecutor(
        address _executor
    ) external onlyArchControllerOwner {
        isApprovedExecutor[_executor] = true;
        emit ExecutorApproved(_executor);
    }

    function removeExecutor(
        address _executor
    ) external onlyArchControllerOwner {
        if (isApprovedExecutor[_executor]) {
            isApprovedExecutor[_executor] = false;
            emit ExecutorRemoved(_executor);
        }
    }

    /**
     * @dev Return the contract name "WildcatCollateralFactoryV1"
     */
    function name() external pure returns (string memory) {
        // Use yul to avoid duplicate memory allocation and reduce code size
        // Uses words at 0x20, 0x40, 0x60
        // 0x20 is overwritten with the ABI offset (32)
        // 0x40 contains the free pointer which will be 1 byte when this function executes.
        // The length of the string (26) is written to the last byte of the free pointer word.
        // 0x60 is the zero slot, so it will not have any dirty bits when this function executes.
        // It is overwritten with the name bytes in the same operation as the length.
        assembly {
            mstore(
                0x53,
                0x1a57696c64636174436F6c6c61746572616c466163746f72795631
            )
            mstore(0x20, 0x20)
            return(0x20, 0x60)
        }
    }

    /**
     * @dev Get the temporarily stored collateral parameters for a contract that is
     *      currently being deployed.
     */
    function getCollateralParameters()
        external
        view
        returns (TmpCollateralParameterStorage memory parameters)
    {
        TmpCollateralParameterStorage
            memory tmp = _getTmpCollateralParameters();

        parameters.borrower = tmp.borrower;
        parameters.collateralToken = tmp.collateralToken;
        parameters.associatedMarket = tmp.associatedMarket;
    }

    ///////////////////////////
    // INTERNAL CODE STORAGE //
    ///////////////////////////

    /**
     * @dev Get the temporary market parameters from transient storage.
     */
    function _getTmpCollateralParameters()
        internal
        view
        returns (TmpCollateralParameterStorage memory parameters)
    {
        return
            abi.decode(
                _tmpCollateralParameters.read(),
                (TmpCollateralParameterStorage)
            );
    }

    /**
     * @dev Set the temporary market parameters in transient storage.
     */
    function _setTmpCollateralParameters(
        TmpCollateralParameterStorage memory parameters
    ) internal {
        _tmpCollateralParameters.write(abi.encode(parameters));
    }

    function contractExists(address _a) internal view returns (bool) {
        uint size;
        assembly {
            size := extcodesize(_a)
        }
        return (size > 0);
    }

    ///////////////////////////
    //  CONTRACT DEPLOYMENT  //
    ///////////////////////////

    function deployCollateralContract(
        address _collateralToken,
        address _associatedMarket,
        bytes32 salt // use collateral token and underlying market to derive salt?
    ) public returns (address collateralContract) {
        collateralContract = LibStoredInitCode.calculateCreate2Address(
            ownCreate2Prefix,
            salt,
            collateralInitCodeHash
        );

        // Do we want this check? Presumably yes, because we'd only want one collateral contract
        // for each market/collateral type - we could deploy several collateral contracts for
        // one market (i.e. WETH, cbBTC collateral against a USDC market), just not two WETHs.
        if (contractExists(collateralContract)) {
            revert CollateralContractAlreadyExists();
        }

        TmpCollateralParameterStorage
            memory tmp = TmpCollateralParameterStorage({
                borrower: IWildcatMarket(_associatedMarket).borrower(),
                collateralToken: _collateralToken,
                associatedMarket: _associatedMarket
            });

        _setTmpCollateralParameters(tmp);
        LibStoredInitCode.create2WithStoredInitCode(
            collateralInitCodeStorage,
            salt
        );
        _tmpCollateralParameters.setEmpty();

        collateralContractList[_associatedMarket].push(
            CollateralContract(
                collateralContract,
                _collateralToken,
                _associatedMarket
            )
        );
    }
}
