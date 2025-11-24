// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import "./SimpleMarketCollateralMultiParty.sol";
import "./libraries/LibStoredInitCode.sol";
import {TransientBytesArray} from "./types/TransientBytesArray.sol";
import "./interfaces/IWildcatArchController.sol";
import "./interfaces/IWildcatMarket.sol";
import "./interfaces/CollateralStruct.sol";
import "v2-protocol/libraries/MathUtils.sol";
import {EnumerableSet} from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract WildcatMarketCollateralFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ========================================================================== */
    /*                            Constants and Storage                           */
    /* ========================================================================== */

    /// @dev Transient storage pointer for collateral parameters.
    TransientBytesArray internal constant _tmpCollateralParameters =
        TransientBytesArray.wrap(
            uint256(keccak256("Transient:TmpCollateralParameterStorage")) - 1
        );

    /// @dev Create2 prefix for collateral contracts - used to calculate the address
    ///      of a collateral contract.
    uint256 internal immutable ownCreate2Prefix =
        LibStoredInitCode.getCreate2Prefix(address(this));

    /// @dev Storage address for collateral contract init code.
    address public immutable collateralInitCodeStorage;

    /// @dev Hash of the collateral contract init code.
    uint256 public immutable collateralInitCodeHash;

    /// @dev Address of the WildcatArchController contract.
    address public immutable archController;

    /// @dev Collateral contracts deployed for each market.
    mapping(address => address[]) public collateralContractsByMarket;

    /// @dev Approved accounts that are allowed to trigger liquidations.
    EnumerableSet.AddressSet internal _approvedExecutors;

    /// @dev Approved exchanges that can be used to execute liquidations.
    EnumerableSet.AddressSet internal _approvedExchanges;

    /* ========================================================================== */
    /*                          Structs, Events & Errors                          */
    /* ========================================================================== */

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

    event ExecutorApproved(address executor);
    event ExecutorRemoved(address executor);
    event ExchangeApproved(address exchange);
    event ExchangeRemoved(address exchange);
    event CollateralContractCreated(
        address collateralContract,
        address collateralToken,
        address associatedMarket
    );

    error NotBorrower();
    error MarketNotRegistered();
    error CallerNotArchControllerOwner();
    error CallerNotOwner();

    /* ========================================================================== */
    /*                                  Modifiers                                 */
    /* ========================================================================== */

    modifier onlyArchControllerOwner() {
        if (msg.sender != IWildcatArchController(archController).owner()) {
            revert CallerNotArchControllerOwner();
        }
        _;
    }

    /* ========================================================================== */
    /*                             Constructor & Name                             */
    /* ========================================================================== */

    constructor(
        address _archController,
        address _collateralInitCodeStorage,
        uint256 _collateralInitCodeHash,
        address[] memory _initialExchanges,
        address[] memory _initialExecutors
    ) {
        archController = _archController;
        collateralInitCodeStorage = _collateralInitCodeStorage;
        collateralInitCodeHash = _collateralInitCodeHash;
        for (uint256 i = 0; i < _initialExchanges.length; i++) {
            if (_approvedExchanges.add(_initialExchanges[i])) {
                emit ExchangeApproved(_initialExchanges[i]);
            }
        }
        for (uint256 i = 0; i < _initialExecutors.length; i++) {
            if (_approvedExecutors.add(_initialExecutors[i])) {
                emit ExecutorApproved(_initialExecutors[i]);
            }
        }
    }

    /// @dev Return the contract name "WildcatCollateralFactoryV1"
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
                0x5a,
                0x1a57696c64636174436F6c6c61746572616c466163746f72795631
            )
            mstore(0x20, 0x20)
            return(0x20, 0x60)
        }
    }

    /* ========================================================================== */
    /*              Executors (accounts able to trigger liquidations)             */
    /* ========================================================================== */

    function isApprovedExecutor(
        address _executor
    ) external view returns (bool) {
        return _approvedExecutors.contains(_executor);
    }

    function approveExecutor(
        address _executor
    ) external onlyArchControllerOwner {
        if (_approvedExecutors.add(_executor)) {
            emit ExecutorApproved(_executor);
        }
    }

    function removeExecutor(
        address _executor
    ) external onlyArchControllerOwner {
        if (_approvedExecutors.remove(_executor)) {
            emit ExecutorRemoved(_executor);
        }
    }

    function getApprovedExecutors() external view returns (address[] memory) {
        return _approvedExecutors.values();
    }

    function getApprovedExecutors(
        uint256 start,
        uint256 end
    ) external view returns (address[] memory arr) {
        uint256 len = _approvedExecutors.length();
        end = MathUtils.min(end, len);
        uint256 count = end - start;
        arr = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            arr[i] = _approvedExecutors.at(start + i);
        }
    }

    function getApprovedExecutorsCount() external view returns (uint256) {
        return _approvedExecutors.length();
    }

    /* ========================================================================== */
    /*                                  Exchanges                                 */
    /* ========================================================================== */

    function isApprovedExchange(
        address _exchange
    ) external view returns (bool) {
        return _approvedExchanges.contains(_exchange);
    }

    function approveExchange(
        address _exchange
    ) external onlyArchControllerOwner {
        if (_approvedExchanges.add(_exchange)) {
            emit ExchangeApproved(_exchange);
        }
    }

    function removeExchange(
        address _exchange
    ) external onlyArchControllerOwner {
        if (_approvedExchanges.remove(_exchange)) {
            emit ExchangeRemoved(_exchange);
        }
    }

    function getApprovedExchanges() external view returns (address[] memory) {
        return _approvedExchanges.values();
    }

    function getApprovedExchanges(
        uint256 start,
        uint256 end
    ) external view returns (address[] memory arr) {
        uint256 len = _approvedExchanges.length();
        end = MathUtils.min(end, len);
        uint256 count = end - start;
        arr = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            arr[i] = _approvedExchanges.at(start + i);
        }
    }

    function getApprovedExchangesCount() external view returns (uint256) {
        return _approvedExchanges.length();
    }

    /* ========================================================================== */
    /*                       Collateral Contracts by Market                       */
    /* ========================================================================== */

    function getCollateralContractsForMarket(
        address marketAddress
    ) public view returns (address[] memory) {
        return collateralContractsByMarket[marketAddress];
    }

    function getCollateralContractsForMarket(
        address marketAddress,
        uint256 startIndex,
        uint256 endIndex
    ) public view returns (address[] memory arr) {
        address[] storage collateralContracts = collateralContractsByMarket[
            marketAddress
        ];

        uint256 len = collateralContracts.length;
        endIndex = MathUtils.min(endIndex, len);

        uint256 count = endIndex - startIndex;
        arr = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            arr[i] = collateralContracts[startIndex + i];
        }
    }

    function getCollateralContractsForMarketCount(
        address marketAddress
    ) external view returns (uint256) {
        return collateralContractsByMarket[marketAddress].length;
    }

    /* ========================================================================== */
    /*                   Constructor Parameters for Deployments                   */
    /* ========================================================================== */

    /**
     * @dev Get the temporarily stored collateral parameters for a contract that is
     *      currently being deployed.
     */
    function getCollateralParameters()
        external
        view
        returns (CollateralParameters memory parameters)
    {
        TmpCollateralParameterStorage
            memory tmp = _getTmpCollateralParameters();

        parameters.borrower = tmp.borrower;
        parameters.collateralToken = tmp.collateralToken;
        parameters.associatedMarket = tmp.associatedMarket;
    }

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

    /* ========================================================================== */
    /*                       Collateral Contract Deployment                       */
    /* ========================================================================== */

    function calculateCollateralContractAddress(
        address marketAddress,
        address collateralToken
    ) public view returns (address) {
        bytes32 salt = keccak256(abi.encode(marketAddress, collateralToken));
        return
            LibStoredInitCode.calculateCreate2Address(
                ownCreate2Prefix,
                salt,
                collateralInitCodeHash
            );
    }

    function deployCollateralContract(
        address marketAddress,
        address collateralToken
    ) public returns (address collateralContract) {
        if (
            !IWildcatArchController(archController).isRegisteredMarket(
                marketAddress
            )
        ) {
            revert MarketNotRegistered();
        }
        if (msg.sender != IWildcatMarket(marketAddress).borrower()) {
            revert NotBorrower();
        }

        bytes32 salt = keccak256(abi.encode(marketAddress, collateralToken));
        TmpCollateralParameterStorage
            memory tmp = TmpCollateralParameterStorage({
                borrower: IWildcatMarket(marketAddress).borrower(),
                collateralToken: collateralToken,
                associatedMarket: marketAddress
            });

        _setTmpCollateralParameters(tmp);
        collateralContract = LibStoredInitCode.create2WithStoredInitCode(
            collateralInitCodeStorage,
            salt
        );
        _tmpCollateralParameters.setEmpty();

        collateralContractsByMarket[marketAddress].push(collateralContract);

        emit CollateralContractCreated(
            collateralContract,
            collateralToken,
            marketAddress
        );
    }
}
