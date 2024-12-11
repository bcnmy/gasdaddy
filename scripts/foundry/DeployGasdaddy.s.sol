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
    bytes32 constant SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT = 0xe37d270a4b697fd49a738e7a7027fe45ab32da92f60226a4fb719794c954eab3; // PM Address => 0x0000a35bb5246c53457a8a28b05b1f0b79348ce1

    // CREATE3 DEPLOYER ADDRESS
    address constant CREATE3_DEPLOYER_ADDRESS = 0x000000aFCC4940A247A53bEa5f3f4602433fe815;

    // CONSTRUCTOR ARGS
    address constant VERIFYING_PAYMASTER_OWNER = 0x2cf491602ad22944D9047282aBC00D3e52F56B37;
    address constant VERIFYING_SIGNER = 0xC6dAB8652E5E9749523bA948F42d5944584E4e73;
    address constant FEE_COLLECTOR = 0x2cf491602ad22944D9047282aBC00D3e52F56B37;
    uint256 constant UNACCOUNTED_GAS = 50_000;
    uint256 constant PAYMASTER_ID_WITHDRAWAL_DELAY = 3600; // 1 hour
    address constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    mapping (uint256 => bytes) public signaturesForMinDeposits;

    Create3Deployer create3Deployer;

    
    function setUp() public {
        create3Deployer = Create3Deployer(CREATE3_DEPLOYER_ADDRESS);
        signaturesForMinDeposits[1e15] = hex'f799f0e37b89b42d667d6cf6ca461bb4e1d9818a5568a640ad89dbe74a16b18b105a3ecbe06828faaf91153bf2238bd5bf9f52cda834eb2ddc81c5665b77901f1b'; //0.001 native token
        signaturesForMinDeposits[1e16] = hex'3d4fc4d9a447fb205cc50dce4b74230f0e0baea776bbce2cced39e1b82f612bc5de05607fdeaf3734f8577a8b829b0dd05bb0fe760e4fe9dda28b729d45c95d21c'; //0.01 native token
        signaturesForMinDeposits[1e17] = hex'f121c54fabc0f95a2baa1cc296135d125f636532d489a9850a0ea3fe7f52694a2954b6f5cd42aca1e2203e7e39108a878477bfe2f90ed6a38ec578199e5586111c'; //0.1 native token
        signaturesForMinDeposits[1e18] = hex'0e2f4921b34b8a2a6ceab67bd7db9655c0e272a725cbb5da84acaad1d023237817a1cb754fd65dd45bebc43312dafb9b53c8e58619da7da5acc9ea96294534141b'; //1 native token
        signaturesForMinDeposits[1e19] = hex'6e559e01580bc8cd18fabef2d0aa018f35dc5cb1aa0c26e8cb8b9c45478382cf0fcc208ad2564d693418957e417a90b9081716fa1c01cba65e8442edaed584541c'; //10 native tokens

    }

    function run(bool check, uint256 minDeposit) public {
        if (check) {
            checkGasDaddyAddresses(minDeposit);
        } else {
            vm.startBroadcast();
            deployGasDaddy(minDeposit);
            vm.stopBroadcast();
        }
    }

    function checkGasDaddyAddresses(uint256 minDeposit) public {

        ///
        /// SPONSORSHIP PAYMASTER
        ///
        bytes memory bytecode = vm.getCode("scripts/bash-deploy/artifacts/BiconomySponsorshipPaymaster/BiconomySponsorshipPaymaster.json");
        bytes memory args = abi.encode(
          VERIFYING_PAYMASTER_OWNER,
          ENTRY_POINT_V07,
          VERIFYING_SIGNER,
          FEE_COLLECTOR,
          UNACCOUNTED_GAS,
          PAYMASTER_ID_WITHDRAWAL_DELAY,
          minDeposit
        );
        address sponsorshipPM = create3Deployer.addressOf(SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT);

        uint256 codeSize;
        assembly {
            codeSize := extcodesize(sponsorshipPM)
        }

        console.log("Sponsorship Paymaster address: ", sponsorshipPM, " || >> Code Size: ", codeSize);

        // Use this block to get initcode hashes to sign
        /* 
        uint256[] memory minDeposits = new uint256[](5);
        minDeposits[0] = 1e15;
        minDeposits[1] = 1e16;
        minDeposits[2] = 1e17;
        minDeposits[3] = 1e18;
        minDeposits[4] = 1e19;

        for (uint256 i = 0; i < minDeposits.length; i++) {
            minDeposit = minDeposits[i];
            args = abi.encode(
              VERIFYING_PAYMASTER_OWNER,
              ENTRY_POINT_V07,
              VERIFYING_SIGNER,
              FEE_COLLECTOR,
              UNACCOUNTED_GAS,
              PAYMASTER_ID_WITHDRAWAL_DELAY,
              minDeposit
            );
            console.log("min deposit: ", (minDeposit));
            console.logBytes32(keccak256(abi.encodePacked(bytecode, args)));
        }
        */

        ///
        /// TOKEN PAYMASTER
        ///

    }   

    function deployGasDaddy(uint256 minDeposit) public {

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
          minDeposit
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
            bytes memory signature = signaturesForMinDeposits[minDeposit];
            sponsorshipPM = create3Deployer.deploy(SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT, initcode, signature);
            console.log("Sponsorship Paymaster deployed at", sponsorshipPM);
        }

        ///
        /// TOKEN PAYMASTER
        ///

    }
}
