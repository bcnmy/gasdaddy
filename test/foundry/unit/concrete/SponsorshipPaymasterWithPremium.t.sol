// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.26;

import { console2 } from "forge-std/src/Console2.sol";
import { NexusTestBase } from "../../base/NexusTestBase.sol";
import { IBiconomySponsorshipPaymaster } from "../../../../contracts/interfaces/IBiconomySponsorshipPaymaster.sol";
import { BiconomySponsorshipPaymaster } from "../../../../contracts/sponsorship/SponsorshipPaymasterWithPremium.sol";
import "account-abstraction/contracts/core/UserOperationLib.sol";

contract SponsorshipPaymasterWithPremiumTest is NexusTestBase {
    BiconomySponsorshipPaymaster public bicoPaymaster;

    function setUp() public {
        setupTestEnvironment();
        // Deploy Sponsorship Paymaster
        bicoPaymaster = new BiconomySponsorshipPaymaster(
            PAYMASTER_OWNER.addr, ENTRYPOINT, PAYMASTER_SIGNER.addr, PAYMASTER_FEE_COLLECTOR.addr
        );
    }

    function test_Deploy() external {
        BiconomySponsorshipPaymaster testArtifact = new BiconomySponsorshipPaymaster(
            PAYMASTER_OWNER.addr, ENTRYPOINT, PAYMASTER_SIGNER.addr, PAYMASTER_FEE_COLLECTOR.addr
        );
        assertEq(testArtifact.owner(), PAYMASTER_OWNER.addr);
        assertEq(address(testArtifact.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(testArtifact.verifyingSigner(), PAYMASTER_SIGNER.addr);
        assertEq(testArtifact.feeCollector(), PAYMASTER_FEE_COLLECTOR.addr);
    }

    function test_CheckInitialPaymasterState() external {
        assertEq(bicoPaymaster.owner(), PAYMASTER_OWNER.addr);
        assertEq(address(bicoPaymaster.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), PAYMASTER_SIGNER.addr);
        assertEq(bicoPaymaster.feeCollector(), PAYMASTER_FEE_COLLECTOR.addr);
    }

    function test_OwnershipTransfer() external {
        vm.startPrank(PAYMASTER_OWNER.addr);
        vm.expectEmit(true, true, false, true, address(bicoPaymaster));
        emit OwnershipTransferred(PAYMASTER_OWNER.addr, DAN_ADDRESS);
        bicoPaymaster.transferOwnership(DAN_ADDRESS);
        assertEq(bicoPaymaster.owner(), DAN_ADDRESS);
        vm.stopPrank();
    }

    function test_RevertIf_OwnershipTransferToZeroAddress() external {
        vm.startPrank(PAYMASTER_OWNER.addr);
        vm.expectRevert(abi.encodeWithSignature("NewOwnerIsZeroAddress()"));
        bicoPaymaster.transferOwnership(address(0));
        vm.stopPrank();
    }

    function test_RevertIf_UnauthorizedOwnershipTransfer() external {
        vm.startPrank(DAN_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        bicoPaymaster.transferOwnership(DAN_ADDRESS);
        vm.stopPrank();
    }

    function test_SetVerifyingSigner() external {
        vm.startPrank(PAYMASTER_OWNER.addr);
        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.VerifyingSignerChanged(
            PAYMASTER_SIGNER.addr, DAN_ADDRESS, PAYMASTER_OWNER.addr
        );
        bicoPaymaster.setSigner(DAN_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), DAN_ADDRESS);
        vm.stopPrank();
    }

    function test_RevertIf_SetVerifyingSignerToContract() external {
        vm.startPrank(PAYMASTER_OWNER.addr);
        vm.expectRevert(abi.encodeWithSignature("VerifyingSignerCannotBeContract()"));
        bicoPaymaster.setSigner(ENTRYPOINT_ADDRESS);
        vm.stopPrank();
    }

    function test_RevertIf_SetVerifyingSignerToZeroAddress() external {
        vm.startPrank(PAYMASTER_OWNER.addr);
        vm.expectRevert(abi.encodeWithSignature("VerifyingSignerCannotBeZero()"));
        bicoPaymaster.setSigner(address(0));
        vm.stopPrank();
    }

    function test_RevertIf_UnauthorizedSetVerifyingSigner() external {
        vm.startPrank(DAN_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        bicoPaymaster.setSigner(DAN_ADDRESS);
        vm.stopPrank();
    }

    function test_SetFeeCollector() external {
        vm.startPrank(PAYMASTER_OWNER.addr);
        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.FeeCollectorChanged(
            PAYMASTER_FEE_COLLECTOR.addr, DAN_ADDRESS, PAYMASTER_OWNER.addr
        );
        bicoPaymaster.setFeeCollector(DAN_ADDRESS);
        assertEq(bicoPaymaster.feeCollector(), DAN_ADDRESS);
        vm.stopPrank();
    }

    function test_RevertIf_SetFeeCollectorToZeroAddress() external {
        vm.startPrank(PAYMASTER_OWNER.addr);
        vm.expectRevert(abi.encodeWithSignature("FeeCollectorCannotBeZero()"));
        bicoPaymaster.setFeeCollector(address(0));
        vm.stopPrank();
    }

    function test_RevertIf_UnauthorizedSetFeeCollector() external {
        vm.startPrank(DAN_ADDRESS);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        bicoPaymaster.setFeeCollector(DAN_ADDRESS);
        vm.stopPrank();
    }

    function test_DepositFor() external {
        uint256 dappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        uint256 depositAmount = 10 ether;
        assertEq(dappPaymasterBalance, 0 ether);
        vm.expectEmit(true, true, false, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasDeposited(DAPP_ACCOUNT.addr, depositAmount);
        bicoPaymaster.depositFor{ value: depositAmount }(DAPP_ACCOUNT.addr);
        dappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        assertEq(dappPaymasterBalance, depositAmount);
    }

    function test_RevertIf_DepositForZeroAddress() external {
        vm.expectRevert(abi.encodeWithSignature("PaymasterIdCannotBeZero()"));
        bicoPaymaster.depositFor{ value: 1 ether }(address(0));
    }

    function test_RevertIf_DepositForZeroValue() external {
        vm.expectRevert(abi.encodeWithSignature("DepositCanNotBeZero()"));
        bicoPaymaster.depositFor{ value: 0 ether }(DAPP_ACCOUNT.addr);
    }

    function test_RevertIf_DepositCalled() external {
        vm.expectRevert("Use depositFor() instead");
        bicoPaymaster.deposit{ value: 1 ether }();
    }

    function test_WithdrawTo() external {
        uint256 depositAmount = 10 ether;
        bicoPaymaster.depositFor{ value: depositAmount }(DAPP_ACCOUNT.addr);
        uint256 danInitialBalance = DAN_ADDRESS.balance;

        vm.startPrank(DAPP_ACCOUNT.addr);
        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasWithdrawn(DAPP_ACCOUNT.addr, DAN_ADDRESS, depositAmount);
        bicoPaymaster.withdrawTo(payable(DAN_ADDRESS), depositAmount);
        uint256 dappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        assertEq(dappPaymasterBalance, 0 ether);
        uint256 expectedDanBalance = danInitialBalance + depositAmount;
        assertEq(DAN_ADDRESS.balance, expectedDanBalance);
        vm.stopPrank();
    }

    function test_RevertIf_WithdrawToZeroAddress() external {
        vm.startPrank(DAPP_ACCOUNT.addr);
        vm.expectRevert(abi.encodeWithSignature("CanNotWithdrawToZeroAddress()"));
        bicoPaymaster.withdrawTo(payable(address(0)), 0 ether);
        vm.stopPrank();
    }

    function test_RevertIf_WithdrawToExceedsBalance() external {
        vm.startPrank(DAPP_ACCOUNT.addr);
        vm.expectRevert("Sponsorship Paymaster: Insufficient funds to withdraw from gas tank");
        bicoPaymaster.withdrawTo(payable(DAN_ADDRESS), 1 ether);
        vm.stopPrank();
    }

    function test_ValidatePaymasterAndPostOp() external {
        uint256 initialDappPaymasterBalance = 10 ether;
        bicoPaymaster.depositFor{ value: initialDappPaymasterBalance }(DAPP_ACCOUNT.addr);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));
        userOp.paymasterAndData = generateAndSignPaymasterData(
            userOp, PAYMASTER_SIGNER, bicoPaymaster, DAPP_ACCOUNT.addr, validUntil, validAfter, 1e6
        );
        userOp.signature = signUserOp(ALICE, userOp);

        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOp);

        ops[0] = userOp;

        vm.startPrank(BUNDLER.addr);
        vm.expectEmit(true, false, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasBalanceDeducted(DAPP_ACCOUNT.addr, 0, userOpHash);
        vm.expectEmit(true, false, false, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.PremiumCollected(DAPP_ACCOUNT.addr, 0);
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        vm.stopPrank();

        uint256 resultingDappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        assertNotEq(initialDappPaymasterBalance, resultingDappPaymasterBalance);
    }

    function test_RevertIf_ValidatePaymasterUserOpWithIncorrectSignatureLength() external {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));
        userOp.paymasterAndData = generateAndSignPaymasterData(
            userOp, PAYMASTER_SIGNER, bicoPaymaster, DAPP_ACCOUNT.addr, validUntil, validAfter, 1e6
        );
        userOp.paymasterAndData = excludeLastNBytes(userOp.paymasterAndData, 2);
        userOp.signature = signUserOp(ALICE, userOp);

        ops[0] = userOp;

        vm.startPrank(BUNDLER.addr);
        vm.expectRevert();
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        vm.stopPrank();
    }

    function test_RevertIf_ValidatePaymasterUserOpWithInvalidPriceMarkUp() external {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));
        userOp.paymasterAndData = generateAndSignPaymasterData(
            userOp, PAYMASTER_SIGNER, bicoPaymaster, DAPP_ACCOUNT.addr, validUntil, validAfter, (2e6 + 1)
        );
        userOp.signature = signUserOp(ALICE, userOp);

        ops[0] = userOp;

        vm.startPrank(BUNDLER.addr);
        vm.expectRevert();
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        vm.stopPrank();
    }

    function test_RevertIf_ValidatePaymasterUserOpWithInsufficientDeposit() external {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));
        userOp.paymasterAndData = generateAndSignPaymasterData(
            userOp, PAYMASTER_SIGNER, bicoPaymaster, DAPP_ACCOUNT.addr, validUntil, validAfter, 1e6
        );
        userOp.signature = signUserOp(ALICE, userOp);

        ops[0] = userOp;

        vm.startPrank(BUNDLER.addr);
        vm.expectRevert();
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        vm.stopPrank();
    }

    function test_Receive() external {
        uint256 initialPaymasterBalance = address(bicoPaymaster).balance;
        uint256 sendAmount = 10 ether;
        vm.startPrank(ALICE_ADDRESS);
        vm.expectEmit(true, true, false, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.Received(ALICE_ADDRESS, sendAmount);
        (bool success,) = address(bicoPaymaster).call{ value: sendAmount }("");
        vm.stopPrank();
        assert(success);
        uint256 resultingPaymasterBalance = address(bicoPaymaster).balance;
        assertEq(resultingPaymasterBalance, initialPaymasterBalance + sendAmount);
    }

    function test_WithdrawEth() external {
        uint256 initialAliceBalance = ALICE_ADDRESS.balance;
        uint256 ethAmount = 10 ether;
        vm.deal(address(bicoPaymaster), ethAmount);
        vm.startPrank(PAYMASTER_OWNER.addr);
        bicoPaymaster.withdrawEth(payable(ALICE_ADDRESS), ethAmount);
        vm.stopPrank();
        assertEq(ALICE_ADDRESS.balance, initialAliceBalance + ethAmount);
        assertEq(address(bicoPaymaster).balance, 0 ether);
    }

    function test_RevertIf_WithdrawEthExceedsBalance() external {
        uint256 ethAmount = 10 ether;
        vm.startPrank(PAYMASTER_OWNER.addr);
        vm.expectRevert("withdraw failed");
        bicoPaymaster.withdrawEth(payable(ALICE_ADDRESS), ethAmount);
        vm.stopPrank();
    }
}
