// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

contract MockSanctionsSentinel {
    mapping(address borrower => mapping(address account => bool)) internal _sanctioned;

    function setSanctioned(
        address borrower,
        address account,
        bool sanctioned
    ) external {
        _sanctioned[borrower][account] = sanctioned;
    }

    function isSanctioned(
        address borrower,
        address account
    ) external view returns (bool) {
        return _sanctioned[borrower][account];
    }
}
