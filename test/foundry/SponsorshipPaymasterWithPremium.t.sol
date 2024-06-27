// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.26;

import { console2 } from "forge-std/src/Console2.sol";

import { NexusTestBase } from "./base/NexusTestBase.sol";

import { BiconomySponsorshipPaymaster } from "../../contracts/sponsorship/SponsorshipPaymasterWithPremium.sol";


contract SponsorshipPaymasterWithPremiumTest is NexusTestBase {
    function setUp() public {
        setupTestEnvironment();
    }

    function testDeploy() external {
        BiconomySponsorshipPaymaster testArtifact = new BiconomySponsorshipPaymaster(BOB_ADDRESS, ENTRYPOINT, ALICE_ADDRESS, CHARLIE_ADDRESS);
        assertEq(address(testArtifact.owner()), BOB_ADDRESS);
        assertEq(address(testArtifact.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(address(testArtifact.verifyingSigner()), ALICE_ADDRESS);
        assertEq(address(testArtifact.feeCollector()), CHARLIE_ADDRESS);
    }
}
