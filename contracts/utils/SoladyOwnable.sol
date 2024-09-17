// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "@solady/auth/Ownable.sol";

contract SoladyOwnable is Ownable {
    constructor(address _owner) Ownable() {
        _initializeOwner(_owner);
    }
}
