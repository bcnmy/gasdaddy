// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.26;

import { console2 } from "forge-std/src/Console2.sol";

import { NexusTestBase } from "./base/NexusTestBase.sol";

import { IBiconomySponsorshipPaymaster } from "./../../contracts/interfaces/IBiconomySponsorshipPaymaster.sol";
import { BiconomySponsorshipPaymaster } from "../../contracts/sponsorship/SponsorshipPaymasterWithPremium.sol";

contract SponsorshipPaymasterWithPremiumTest is NexusTestBase {
    BiconomySponsorshipPaymaster public bicoPaymaster;

    function setUp() public {
        setupTestEnvironment();
        // Deploy Sponsorship Paymaster
        bicoPaymaster = new BiconomySponsorshipPaymaster(ALICE_ADDRESS, ENTRYPOINT, BOB_ADDRESS, CHARLIE_ADDRESS);
    }

    function test_Deploy() external {
        BiconomySponsorshipPaymaster testArtifact =
            new BiconomySponsorshipPaymaster(ALICE_ADDRESS, ENTRYPOINT, BOB_ADDRESS, CHARLIE_ADDRESS);
        assertEq(testArtifact.owner(), ALICE_ADDRESS);
        assertEq(address(testArtifact.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(testArtifact.verifyingSigner(), BOB_ADDRESS);
        assertEq(testArtifact.feeCollector(), CHARLIE_ADDRESS);
    }

    function test_CheckStates() external {
        assertEq(bicoPaymaster.owner(), ALICE_ADDRESS);
        assertEq(address(bicoPaymaster.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), BOB_ADDRESS);
        assertEq(bicoPaymaster.feeCollector(), CHARLIE_ADDRESS);
    }

    function test_OwnershipTransfer() external {
        vm.startPrank(ALICE_ADDRESS);
        assertEq(bicoPaymaster.owner(), ALICE_ADDRESS);
        vm.expectEmit(true, true, false, true, address(bicoPaymaster));
        emit OwnershipTransferred(ALICE_ADDRESS, DAN_ADDRESS);
        bicoPaymaster.transferOwnership(DAN_ADDRESS);
        assertEq(bicoPaymaster.owner(), DAN_ADDRESS);
        vm.stopPrank();
    }

    function test_RevertIf_OwnershipTransferToZeroAddress() external {
        vm.startPrank(ALICE_ADDRESS);
        assertEq(bicoPaymaster.owner(), ALICE_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("NewOwnerIsZeroAddress()"));
        bicoPaymaster.transferOwnership(address(0));
        vm.stopPrank();
    }

    function test_RevertIf_UnauthorizedOwnershipTransfer() external {
        vm.startPrank(DAN_ADDRESS);
        assertEq(bicoPaymaster.owner(), ALICE_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        bicoPaymaster.transferOwnership(DAN_ADDRESS);
        vm.stopPrank();
    }

    function test_SetVerifyingSigner() external {
        vm.startPrank(ALICE_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), BOB_ADDRESS);
        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.VerifyingSignerChanged(BOB_ADDRESS, DAN_ADDRESS, ALICE_ADDRESS);
        bicoPaymaster.setSigner(DAN_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), DAN_ADDRESS);
        vm.stopPrank();
    }

    function test_RevertIf_SetVerifyingSignerToZeroAddress() external {
        vm.startPrank(ALICE_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), BOB_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("VerifyingSignerCannotBeZero()"));
        bicoPaymaster.setSigner(address(0));
        vm.stopPrank();
    }

    function test_RevertIf_UnauthorizedSetVerifyingSigner() external {
        vm.startPrank(DAN_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), BOB_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        bicoPaymaster.setSigner(DAN_ADDRESS);
        vm.stopPrank();
    }

    function test_SetFeeCollector() external {
        vm.startPrank(ALICE_ADDRESS);
        assertEq(bicoPaymaster.feeCollector(), CHARLIE_ADDRESS);
        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.FeeCollectorChanged(CHARLIE_ADDRESS, DAN_ADDRESS, ALICE_ADDRESS);
        bicoPaymaster.setFeeCollector(DAN_ADDRESS);
        assertEq(bicoPaymaster.feeCollector(), DAN_ADDRESS);
        vm.stopPrank();
    }

    function test_RevertIf_SetFeeCollectorToZeroAddress() external {
        vm.startPrank(ALICE_ADDRESS);
        assertEq(bicoPaymaster.feeCollector(), CHARLIE_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("FeeCollectorCannotBeZero()"));
        bicoPaymaster.setFeeCollector(address(0));
        vm.stopPrank();
    }

    function test_RevertIf_UnauthorizedSetFeeCollector() external {
        vm.startPrank(DAN_ADDRESS);
        assertEq(bicoPaymaster.feeCollector(), CHARLIE_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        bicoPaymaster.setFeeCollector(DAN_ADDRESS);
        vm.stopPrank();
    }

    function test_DepositFor() external {
        uint256 dappPaymasterBalance = bicoPaymaster.getBalance(DAPP_PAYMASTER.addr);
        uint256 depositAmount = 10 ether;
        assertEq(dappPaymasterBalance, 0 ether);
        vm.expectEmit(true, true, false, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasDeposited(DAPP_PAYMASTER.addr, depositAmount);
        bicoPaymaster.depositFor{ value: depositAmount }(DAPP_PAYMASTER.addr);
        dappPaymasterBalance = bicoPaymaster.getBalance(DAPP_PAYMASTER.addr);
        assertEq(dappPaymasterBalance, depositAmount);
    }

    function test_RevertIf_DepositForZeroAddress() external {
        vm.expectRevert(abi.encodeWithSignature("PaymasterIdCannotBeZero()"));
        bicoPaymaster.depositFor{ value: 1 ether }(address(0));
    }

    function test_RevertIf_DepositForZeroValue() external {
        vm.expectRevert(abi.encodeWithSignature("DepositCanNotBeZero()"));
        bicoPaymaster.depositFor{ value: 0 ether }(DAPP_PAYMASTER.addr);
    }

    function test_RevertIf_DepositCalled() external {
        vm.expectRevert("Use depositFor() instead");
        bicoPaymaster.deposit{ value: 1 ether }();
    }

    function test_WithdrawTo() external {
        uint256 depositAmount = 10 ether;
        bicoPaymaster.depositFor{ value: depositAmount }(DAPP_PAYMASTER.addr);
        uint256 danInitialBalance = DAN_ADDRESS.balance;

        vm.startPrank(DAPP_PAYMASTER.addr);
        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasWithdrawn(DAPP_PAYMASTER.addr, DAN_ADDRESS, depositAmount);
        bicoPaymaster.withdrawTo(payable(DAN_ADDRESS), depositAmount);
        uint256 dappPaymasterBalance = bicoPaymaster.getBalance(DAPP_PAYMASTER.addr);
        assertEq(dappPaymasterBalance, 0 ether);
        uint256 expectedDanBalance = danInitialBalance + depositAmount;
        assertEq(DAN_ADDRESS.balance, expectedDanBalance);
        vm.stopPrank();
    }

    function test_RevertIf_WithdrawToZeroAddress() external {
        vm.startPrank(DAPP_PAYMASTER.addr);
        vm.expectRevert(abi.encodeWithSignature("CanNotWithdrawToZeroAddress()"));
        bicoPaymaster.withdrawTo(payable(address(0)), 0 ether);
        vm.stopPrank();
    }

    function test_RevertIf_WithdrawToExceedsBalance() external {
        vm.startPrank(DAPP_PAYMASTER.addr);
        vm.expectRevert("Sponsorship Paymaster: Insufficient funds to withdraw from gas tank");
        bicoPaymaster.withdrawTo(payable(DAN_ADDRESS), 1 ether);
        vm.stopPrank();
    }
}
