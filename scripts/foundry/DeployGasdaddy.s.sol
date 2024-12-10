// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {DeterministicDeployerLib} from "./utils/DeterministicDeployerLib.sol";

interface Create3Deployer {
    function addressOf(bytes32 salt) external view returns (address);

    function deploy(bytes32 salt, bytes calldata creationCode, bytes calldata signature) external returns (address);
}

contract DeployGasdaddy is Script {
    // SALTS
    bytes32 constant SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT = 0x0000000cc000000000000000000000000000000048da08a98903870005d16743;

    // CREATE3 DEPLOYER ADDRESS
    address constant CREATE3_DEPLOYER_ADDRESS = 0x000000aFCC4940A247A53bEa5f3f4602433fe815;

    // CONSTRUCTOR ARGS
    address constant VERIFYING_PAYMASTER_OWNER = 0x2cf491602ad22944D9047282aBC00D3e52F56B37;
    address constant VERIFYING_SIGNER = 0xC6dAB8652E5E9749523bA948F42d5944584E4e73;
    address constant FEE_COLLECTOR = 0x2cf491602ad22944D9047282aBC00D3e52F56B37;
    uint256 constant UNACCOUNTED_GAS = 50_000;
    uint256 constant PAYMASTER_ID_WITHDRAWAL_DELAY = 3600; // 1 hour
    uint256 constant MIN_DEPOSIT = 1e15; 
    address constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    Create3Deployer create3Deployer;

    
    function setUp() public {
        create3Deployer = Create3Deployer(CREATE3_DEPLOYER_ADDRESS);
    }

    function run(bool check) public {
        if (check) {
            checkGasDaddyAddresses();
        } else {
            deployGasDaddy();
        }
    }

    function checkGasDaddyAddresses() public {
        bytes memory bytecode = vm.getCode("scripts/bash-deploy/artifacts/BiconomySponsorshipPaymaster/BiconomySponsorshipPaymaster.json");
        bytes memory args = abi.encode(
          VERIFYING_PAYMASTER_OWNER,
          ENTRY_POINT_V07,
          VERIFYING_SIGNER,
          FEE_COLLECTOR,
          UNACCOUNTED_GAS,
          PAYMASTER_ID_WITHDRAWAL_DELAY,
          MIN_DEPOSIT
        );
        address sponsorshipPM = create3Deployer.addressOf(SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT);

        uint256 codeSize;
        assembly {
            codeSize := extcodesize(sponsorshipPM)
        }

        console.log("Sponsorship Paymaster address: ", sponsorshipPM, " || >> Code Size: ", codeSize);

        //initcode hash to look for the salt
        //console.logBytes32(keccak256(abi.encodePacked(bytecode, args)));
    }   

    function deployGasDaddy() public {

        //
        // SPONSORSHIP PAYMASTER
        //
        bytes memory bytecode = vm.getCode("scripts/bash-deploy/artifacts/BiconomySponsorshipPaymaster/BiconomySponsorshipPaymaster.json");
        bytes memory args = abi.encode(
          VERIFYING_PAYMASTER_OWNER,
          ENTRY_POINT_V07,
          VERIFYING_SIGNER,
          FEE_COLLECTOR,
          UNACCOUNTED_GAS,
          PAYMASTER_ID_WITHDRAWAL_DELAY,
          MIN_DEPOSIT
        );
        address sponsorshipPM = create3Deployer.addressOf(SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT);
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(sponsorshipPM)
        }
        if (codeSize > 0) {
            console.log("Sponsorship Paymaster already deployed at", sponsorshipPM);
        } else {
            bytes memory initcode = abi.encodePacked(bytecode, args);
            bytes memory signature = hex'f799f0e37b89b42d667d6cf6ca461bb4e1d9818a5568a640ad89dbe74a16b18b105a3ecbe06828faaf91153bf2238bd5bf9f52cda834eb2ddc81c5665b77901f1b'; //pre-computed signature
            sponsorshipPM = create3Deployer.deploy(SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT, initcode, signature);
            console.log("Sponsorship Paymaster deployed at", sponsorshipPM);
        }

        //
        //
        //
    }
}
