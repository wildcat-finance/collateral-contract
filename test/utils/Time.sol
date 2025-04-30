// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Vm, VmSafe} from "forge-std/Vm.sol";

address constant VM_ADDRESS = address(
    uint160(uint256(keccak256("hevm cheat code")))
);
Vm constant vm = Vm(VM_ADDRESS);

contract FastForward {
    constructor(uint256 time) {
        vm.warp(block.timestamp + time);
        assembly {
            selfdestruct(caller())
        }
    }
}

// Utility functions to get around stack optimizations by ir pipeline
// causing timestamp after warp to match timestamp before
function fastForward(uint256 time) {
    new FastForward(time);
}
