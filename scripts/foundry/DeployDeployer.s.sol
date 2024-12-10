// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {DeterministicDeployerLib} from "./utils/DeterministicDeployerLib.sol";

contract DeployDeployer is Script {

    bytes32 constant CREATE3_DEPLOYER_DEPLOYMENT_SALT = 0x00000000000000000000000000000000000000005328f95dfa58cf03e311ce44;
    address constant DEPLOYER_OWNER = 0x336A8f5251F3b0723d04FBDD25858fca02BB22E3;
    bytes32 constant DEPLOYER_BYTECODE_HASH = 0x2b2eaf7fbe1e33745154ad0e5e3e0dc0f415dc619e233ee0a317a9c1e7d53657;

    function setUp() public {}

    function run() public returns (address) {
        bytes memory bytecode = vm.getCode("scripts/bash-deploy/artifacts/Deployer/Deployer.json");
        bytes memory args = abi.encode(DEPLOYER_OWNER);

        address expectedDeployer = DeterministicDeployerLib.computeAddress(bytecode, args, CREATE3_DEPLOYER_DEPLOYMENT_SALT);

        // initcode hash to look for the salt
        // console.logBytes32(keccak256(abi.encodePacked(bytecode, args)));

        bytes32 deployerBytecodeHash;
        uint256 codeLength;

        assembly {
            codeLength := extcodesize(expectedDeployer)
            deployerBytecodeHash := extcodehash(expectedDeployer)
        }

        //console.logBytes32(deployerBytecodeHash);
        //console.log("Size", codeLength);

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
