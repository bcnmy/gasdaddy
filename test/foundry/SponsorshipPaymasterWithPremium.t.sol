// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.26;

import { console2 } from "forge-std/src/Console2.sol";

import { NexusTestBase } from "./base/NexusTestBase.sol";

import { BiconomySponsorshipPaymaster } from "../../contracts/sponsorship/SponsorshipPaymasterWithPremium.sol";

contract SponsorshipPaymasterWithPremiumTest is NexusTestBase {
    BiconomySponsorshipPaymaster public bicoPaymaster;

    function setUp() public {
        setupTestEnvironment();
        // Deploy Sponsorship Paymaster
        bicoPaymaster = new BiconomySponsorshipPaymaster(ALICE_ADDRESS, ENTRYPOINT, BOB_ADDRESS, CHARLIE_ADDRESS);
    }

    function testDeploy() external {
        BiconomySponsorshipPaymaster testArtifact =
            new BiconomySponsorshipPaymaster(ALICE_ADDRESS, ENTRYPOINT, BOB_ADDRESS, CHARLIE_ADDRESS);
        assertEq(testArtifact.owner(), ALICE_ADDRESS);
        assertEq(address(testArtifact.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(testArtifact.verifyingSigner(), BOB_ADDRESS);
        assertEq(testArtifact.feeCollector(), CHARLIE_ADDRESS);
    }

    function testCheckStates() external {
        assertEq(bicoPaymaster.owner(), ALICE_ADDRESS);
        assertEq(address(bicoPaymaster.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), BOB_ADDRESS);
        assertEq(bicoPaymaster.feeCollector(), CHARLIE_ADDRESS);
    }

    function testOwnershipTransfer() external {
        vm.startPrank(ALICE_ADDRESS);
        assertEq(bicoPaymaster.owner(), ALICE_ADDRESS);
        bicoPaymaster.transferOwnership(DAN_ADDRESS);
        assertEq(bicoPaymaster.owner(), DAN_ADDRESS);
        vm.stopPrank();
    }

    function testInvalidOwnershipTransfer() external {
        vm.startPrank(ALICE_ADDRESS);
        assertEq(bicoPaymaster.owner(), ALICE_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("NewOwnerIsZeroAddress()"));
        bicoPaymaster.transferOwnership(address(0));
        vm.stopPrank();

        vm.startPrank(DAN_ADDRESS);
        assertEq(bicoPaymaster.owner(), ALICE_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        bicoPaymaster.transferOwnership(DAN_ADDRESS);
        vm.stopPrank();
    }

    function testChangingVerifyingSigner() external {
        vm.startPrank(ALICE_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), BOB_ADDRESS);
        bicoPaymaster.setSigner(DAN_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), DAN_ADDRESS);
        vm.stopPrank();
    }

    function testInvalidChangingVerifyingSigner() external {
        vm.startPrank(ALICE_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), BOB_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("VerifyingSignerCannotBeZero()"));
        bicoPaymaster.setSigner(address(0));
        vm.stopPrank();

        vm.startPrank(DAN_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), BOB_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        bicoPaymaster.setSigner(DAN_ADDRESS);
        vm.stopPrank();
    }

    function testChangingFeeCollector() external {
        vm.startPrank(ALICE_ADDRESS);
        assertEq(bicoPaymaster.feeCollector(), CHARLIE_ADDRESS);
        bicoPaymaster.setFeeCollector(DAN_ADDRESS);
        assertEq(bicoPaymaster.feeCollector(), DAN_ADDRESS);
        vm.stopPrank();
    }

    function testInvalidChangingFeeCollector() external {
        vm.startPrank(ALICE_ADDRESS);
        assertEq(bicoPaymaster.feeCollector(), CHARLIE_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("FeeCollectorCannotBeZero()"));
        bicoPaymaster.setFeeCollector(address(0));
        vm.stopPrank();

        vm.startPrank(DAN_ADDRESS);
        assertEq(bicoPaymaster.feeCollector(), CHARLIE_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        bicoPaymaster.setFeeCollector(DAN_ADDRESS);
        vm.stopPrank();
    }

    function testDepositFor() external {
        uint256 dappBalance = bicoPaymaster.getBalance(DAPP_PAYMASTER.addr);
        uint256 depositAmount = 10 ether;
        assertEq(dappBalance, 0 ether);
        bicoPaymaster.depositFor{ value: depositAmount }(DAPP_PAYMASTER.addr);
        dappBalance = bicoPaymaster.getBalance(DAPP_PAYMASTER.addr);
        assertEq(dappBalance, depositAmount);
    }

    function testInvalidDepositFor() external {
        vm.expectRevert(abi.encodeWithSignature("PaymasterIdCannotBeZero()"));
        bicoPaymaster.depositFor{ value: 1 ether }(address(0));

        vm.expectRevert(abi.encodeWithSignature("DepositCanNotBeZero()"));
        bicoPaymaster.depositFor{ value: 0 ether }(DAPP_PAYMASTER.addr);
    }

    function testInvalidDeposit() external {
        vm.expectRevert("Use depositFor() instead");
        bicoPaymaster.deposit{ value: 1 ether }();
    }
}
