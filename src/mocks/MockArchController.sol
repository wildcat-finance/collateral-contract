// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

contract MockArchController {
    address public owner;
    error NotOwner();

    constructor() {
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) public {
        if (msg.sender != owner) {
            revert NotOwner();
        }
        owner = newOwner;
    }

    function isRegisteredMarket(address market) public view returns (bool) {
        return true;
    }
}
