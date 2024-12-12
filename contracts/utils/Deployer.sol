//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.27;

import "./Create3.sol";
import "./SoladyOwnable.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

contract Deployer is SoladyOwnable {
    event ContractDeployed(address indexed contractAddress);
    error InvalidBytecodeSignature();

    using ECDSA for bytes32;

    constructor(address _owner) SoladyOwnable(_owner) {}

    function deploy(bytes32 _salt, bytes calldata _creationCode, bytes calldata signature) external returns (address deployedContract) {
        bytes32 hash = keccak256(abi.encode(_creationCode, _salt, block.chainid));
        if (!_verifySignature(hash, signature)) revert InvalidBytecodeSignature();
        deployedContract = Create3.create3(_salt, _creationCode);
        emit ContractDeployed(deployedContract);
    }

    function deploy(bytes32 _salt, bytes calldata _creationCode) onlyOwner external returns (address deployedContract) {   
        deployedContract = Create3.create3(_salt, _creationCode);
        emit ContractDeployed(deployedContract);
    }

    function addressOf(bytes32 _salt) external view returns (address) {
        return Create3.addressOf(_salt);
    }

    function _verifySignature(bytes32 hash, bytes calldata signature) internal view returns (bool) {
        if (hash.recoverCalldata(signature) == owner())
            return true;
        if (hash.toEthSignedMessageHash().recoverCalldata(signature) == owner())
            return true;
        return false;
    }
}
