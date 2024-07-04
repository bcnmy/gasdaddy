// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.26;

import { NexusTestBase } from "../../base/NexusTestBase.sol";
import { IBiconomySponsorshipPaymaster } from "../../../../contracts/interfaces/IBiconomySponsorshipPaymaster.sol";
import { BiconomySponsorshipPaymaster } from "../../../../contracts/sponsorship/SponsorshipPaymasterWithPremium.sol";
import { PackedUserOperation } from "account-abstraction/contracts/core/UserOperationLib.sol";
import { MockToken } from "./../../../../lib/nexus/contracts/mocks/MockToken.sol";

contract TestSponsorshipPaymasterWithPremium is NexusTestBase {
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

    function test_CheckInitialPaymasterState() external view {
        assertEq(bicoPaymaster.owner(), PAYMASTER_OWNER.addr);
        assertEq(address(bicoPaymaster.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), PAYMASTER_SIGNER.addr);
        assertEq(bicoPaymaster.feeCollector(), PAYMASTER_FEE_COLLECTOR.addr);
    }

    function test_OwnershipTransfer() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectEmit(true, true, false, true, address(bicoPaymaster));
        emit OwnershipTransferred(PAYMASTER_OWNER.addr, DAN_ADDRESS);
        bicoPaymaster.transferOwnership(DAN_ADDRESS);
        assertEq(bicoPaymaster.owner(), DAN_ADDRESS);
    }

    function test_RevertIf_OwnershipTransferToZeroAddress() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectRevert(abi.encodeWithSelector(NewOwnerIsZeroAddress.selector));
        bicoPaymaster.transferOwnership(address(0));
    }

    function test_RevertIf_UnauthorizedOwnershipTransfer() external {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        bicoPaymaster.transferOwnership(DAN_ADDRESS);
    }

    function test_SetVerifyingSigner() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.VerifyingSignerChanged(
            PAYMASTER_SIGNER.addr, DAN_ADDRESS, PAYMASTER_OWNER.addr
        );
        bicoPaymaster.setSigner(DAN_ADDRESS);
        assertEq(bicoPaymaster.verifyingSigner(), DAN_ADDRESS);
    }

    function test_RevertIf_SetVerifyingSignerToContract() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectRevert(abi.encodeWithSelector(VerifyingSignerCanNotBeContract.selector));
        bicoPaymaster.setSigner(ENTRYPOINT_ADDRESS);
    }

    function test_RevertIf_SetVerifyingSignerToZeroAddress() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectRevert(abi.encodeWithSelector(VerifyingSignerCanNotBeZero.selector));
        bicoPaymaster.setSigner(address(0));
    }

    function test_RevertIf_UnauthorizedSetVerifyingSigner() external {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        bicoPaymaster.setSigner(DAN_ADDRESS);
    }

    function test_SetFeeCollector() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.FeeCollectorChanged(
            PAYMASTER_FEE_COLLECTOR.addr, DAN_ADDRESS, PAYMASTER_OWNER.addr
        );
        bicoPaymaster.setFeeCollector(DAN_ADDRESS);
        assertEq(bicoPaymaster.feeCollector(), DAN_ADDRESS);
    }

    function test_RevertIf_SetFeeCollectorToZeroAddress() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectRevert(abi.encodeWithSelector(FeeCollectorCanNotBeZero.selector));
        bicoPaymaster.setFeeCollector(address(0));
    }

    function test_RevertIf_UnauthorizedSetFeeCollector() external {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        bicoPaymaster.setFeeCollector(DAN_ADDRESS);
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
        vm.expectRevert(abi.encodeWithSelector(PaymasterIdCanNotBeZero.selector));
        bicoPaymaster.depositFor{ value: 1 ether }(address(0));
    }

    function test_RevertIf_DepositForZeroValue() external {
        vm.expectRevert(abi.encodeWithSelector(DepositCanNotBeZero.selector));
        bicoPaymaster.depositFor{ value: 0 ether }(DAPP_ACCOUNT.addr);
    }

    function test_RevertIf_DepositCalled() external {
        vm.expectRevert(abi.encodeWithSelector(UseDepositForInstead.selector));
        bicoPaymaster.deposit{ value: 1 ether }();
    }

    function test_WithdrawTo() external prankModifier(DAPP_ACCOUNT.addr) {
        uint256 depositAmount = 10 ether;
        bicoPaymaster.depositFor{ value: depositAmount }(DAPP_ACCOUNT.addr);
        uint256 danInitialBalance = DAN_ADDRESS.balance;

        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasWithdrawn(DAPP_ACCOUNT.addr, DAN_ADDRESS, depositAmount);
        bicoPaymaster.withdrawTo(payable(DAN_ADDRESS), depositAmount);

        uint256 dappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        assertEq(dappPaymasterBalance, 0 ether);
        uint256 expectedDanBalance = danInitialBalance + depositAmount;
        assertEq(DAN_ADDRESS.balance, expectedDanBalance);
    }

    function test_RevertIf_WithdrawToZeroAddress() external prankModifier(DAPP_ACCOUNT.addr) {
        vm.expectRevert(abi.encodeWithSelector(CanNotWithdrawToZeroAddress.selector));
        bicoPaymaster.withdrawTo(payable(address(0)), 0 ether);
    }

    function test_RevertIf_WithdrawToExceedsBalance() external prankModifier(DAPP_ACCOUNT.addr) {
        vm.expectRevert(abi.encodeWithSelector(InsufficientFundsInGasTank.selector));
        bicoPaymaster.withdrawTo(payable(DAN_ADDRESS), 1 ether);
    }

    function test_ValidatePaymasterAndPostOp() external {
        uint256 initialDappPaymasterBalance = 10 ether;
        bicoPaymaster.depositFor{ value: initialDappPaymasterBalance }(DAPP_ACCOUNT.addr);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));
        userOp.paymasterAndData = generateAndSignPaymasterData(
            userOp, PAYMASTER_SIGNER, bicoPaymaster, 3e6, 3e6, DAPP_ACCOUNT.addr, validUntil, validAfter, 1e6
        );
        userOp.signature = signUserOp(ALICE, userOp);

        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOp);

        ops[0] = userOp;

        vm.expectEmit(true, false, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasBalanceDeducted(DAPP_ACCOUNT.addr, 0, userOpHash);
        vm.expectEmit(true, false, false, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.PremiumCollected(DAPP_ACCOUNT.addr, 0);
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));

        uint256 resultingDappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        assertNotEq(initialDappPaymasterBalance, resultingDappPaymasterBalance);
    }

    function test_RevertIf_ValidatePaymasterUserOpWithIncorrectSignatureLength() external {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));
        userOp.paymasterAndData = generateAndSignPaymasterData(
            userOp, PAYMASTER_SIGNER, bicoPaymaster, 3e6, 3e6, DAPP_ACCOUNT.addr, validUntil, validAfter, 1e6
        );
        userOp.paymasterAndData = excludeLastNBytes(userOp.paymasterAndData, 2);
        userOp.signature = signUserOp(ALICE, userOp);

        ops[0] = userOp;

        vm.expectRevert();
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
    }

    function test_RevertIf_ValidatePaymasterUserOpWithInvalidPriceMarkUp() external {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));
        userOp.paymasterAndData = generateAndSignPaymasterData(
            userOp, PAYMASTER_SIGNER, bicoPaymaster, 3e6, 3e6, DAPP_ACCOUNT.addr, validUntil, validAfter, 1e6
        );
        userOp.signature = signUserOp(ALICE, userOp);

        ops[0] = userOp;

        vm.expectRevert();
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
    }

    function test_RevertIf_ValidatePaymasterUserOpWithInsufficientDeposit() external {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));
        userOp.paymasterAndData = generateAndSignPaymasterData(
            userOp, PAYMASTER_SIGNER, bicoPaymaster, 3e6, 3e6, DAPP_ACCOUNT.addr, validUntil, validAfter, 1e6
        );
        userOp.signature = signUserOp(ALICE, userOp);

        ops[0] = userOp;

        vm.expectRevert();
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
    }

    function test_Receive() external prankModifier(ALICE_ADDRESS) {
        uint256 initialPaymasterBalance = address(bicoPaymaster).balance;
        uint256 sendAmount = 10 ether;

        vm.expectEmit(true, true, false, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.Received(ALICE_ADDRESS, sendAmount);
        (bool success,) = address(bicoPaymaster).call{ value: sendAmount }("");

        assert(success);
        uint256 resultingPaymasterBalance = address(bicoPaymaster).balance;
        assertEq(resultingPaymasterBalance, initialPaymasterBalance + sendAmount);
    }

    function test_WithdrawEth() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 initialAliceBalance = ALICE_ADDRESS.balance;
        uint256 ethAmount = 10 ether;
        vm.deal(address(bicoPaymaster), ethAmount);

        bicoPaymaster.withdrawEth(payable(ALICE_ADDRESS), ethAmount);
        vm.stopPrank();

        assertEq(ALICE_ADDRESS.balance, initialAliceBalance + ethAmount);
        assertEq(address(bicoPaymaster).balance, 0 ether);
    }

    function test_RevertIf_WithdrawEthExceedsBalance() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 ethAmount = 10 ether;
        vm.expectRevert(abi.encodeWithSelector(WithdrawalFailed.selector));
        bicoPaymaster.withdrawEth(payable(ALICE_ADDRESS), ethAmount);
    }

    function test_WithdrawErc20() external prankModifier(PAYMASTER_OWNER.addr) {
        MockToken token = new MockToken("Token", "TKN");
        uint256 mintAmount = 10 * (10 ** token.decimals());
        token.mint(address(bicoPaymaster), mintAmount);

        assertEq(token.balanceOf(address(bicoPaymaster)), mintAmount);
        assertEq(token.balanceOf(ALICE_ADDRESS), 0);

        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.TokensWithdrawn(
            address(token), ALICE_ADDRESS, mintAmount, PAYMASTER_OWNER.addr
        );
        bicoPaymaster.withdrawERC20(token, ALICE_ADDRESS, mintAmount);

        assertEq(token.balanceOf(address(bicoPaymaster)), 0);
        assertEq(token.balanceOf(ALICE_ADDRESS), mintAmount);
    }

    function test_RevertIf_WithdrawErc20ToZeroAddress() external prankModifier(PAYMASTER_OWNER.addr) {
        MockToken token = new MockToken("Token", "TKN");
        uint256 mintAmount = 10 * (10 ** token.decimals());
        token.mint(address(bicoPaymaster), mintAmount);

        vm.expectRevert(abi.encodeWithSelector(CanNotWithdrawToZeroAddress.selector));
        bicoPaymaster.withdrawERC20(token, address(0), mintAmount);
    }
}
