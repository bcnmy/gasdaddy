// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {DeterministicDeployerLib} from "./utils/DeterministicDeployerLib.sol";

contract DeployDeployer is Script {

    bytes32 constant CREATE3_DEPLOYER_DEPLOYMENT_SALT = 0x000000000000000000000000000000000000000068be161e3f742b0423335623; // => 0x0000003d8fE88f1591774CCD958baF0211Ee2183
    address constant DEPLOYER_OWNER = 0x336A8f5251F3b0723d04FBDD25858fca02BB22E3;
    bytes32 constant DEPLOYER_BYTECODE_HASH = 0xb474e2c7cd2df923dc66b1fbf61eb752b66b7aecb94e055878c3c75061de219c;

    function setUp() public {}

    function run() public returns (address) {
        bytes memory bytecode = vm.getCode("scripts/bash-deploy/artifacts/Deployer/Deployer.json");
        bytes memory args = abi.encode(DEPLOYER_OWNER);

        address expectedDeployer = DeterministicDeployerLib.computeAddress(bytecode, args, CREATE3_DEPLOYER_DEPLOYMENT_SALT);

        // initcode hash to look for the salt
        console.log("Deployer bytecode hash for salt generation: ");
        console.logBytes32(keccak256(abi.encodePacked(bytecode, args)));

        bytes32 deployerBytecodeHash;
        uint256 codeLength;

        assembly {
            codeLength := extcodesize(expectedDeployer)
            deployerBytecodeHash := extcodehash(expectedDeployer)
        }

        if (codeLength != 0) {
            if (deployerBytecodeHash != DEPLOYER_BYTECODE_HASH) {
                revert("Deployer bytecode hash mismatch");
            }
            console.log("Deployer deployed at", expectedDeployer);
            return expectedDeployer;
        }

        address deployedDeployer = DeterministicDeployerLib.broadcastDeploy(bytecode, args, CREATE3_DEPLOYER_DEPLOYMENT_SALT);

        assembly {
            codeLength := extcodesize(deployedDeployer)
        }

        //console.log("Expected deployer address", expectedDeployer);
        //console.log("Deployed deployer address", deployedDeployer);

        if (deployedDeployer == expectedDeployer && codeLength > 0) {
            console.log("Deployer deployed at", deployedDeployer);
        } else {
            revert("Deployer deployment failed");
        }
        return deployedDeployer;
    }   
}
