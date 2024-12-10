// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "solady/auth/Ownable.sol";

contract SoladyOwnable is Ownable {
    constructor(address _owner) Ownable() {
        assembly {
            if iszero(shl(96, _owner)) {
                mstore(0x00, 0x7448fbae) // `NewOwnerIsZeroAddress()`.
                revert(0x1c, 0x04)
            }
        }
        _initializeOwner(_owner);
    }
}
