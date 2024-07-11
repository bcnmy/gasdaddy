// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable } from "solady/src/auth/Ownable.sol";

contract SoladyOwnable is Ownable {
    constructor(address _owner) Ownable() {
        _initializeOwner(_owner);
    }
}
