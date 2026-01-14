// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

contract MockWildcatArchController {
    address public owner;
    mapping(address => bool) public isRegisteredMarket;

    constructor(address _owner) {
        owner = _owner;
    }

    function registerMarket(address market) public {
        isRegisteredMarket[market] = true;
    }

    function unregisterMarket(address market) public {
        isRegisteredMarket[market] = false;
    }
}
