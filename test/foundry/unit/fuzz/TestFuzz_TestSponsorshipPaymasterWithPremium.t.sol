// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.26;

import { NexusTestBase } from "../../base/NexusTestBase.sol";
import { IBiconomySponsorshipPaymaster } from "../../../../contracts/interfaces/IBiconomySponsorshipPaymaster.sol";
import { BiconomySponsorshipPaymaster } from "../../../../contracts/sponsorship/SponsorshipPaymasterWithPremium.sol";
import { MockToken } from "./../../../../lib/nexus/contracts/mocks/MockToken.sol";
import { PackedUserOperation } from "account-abstraction/contracts/interfaces/PackedUserOperation.sol";

contract TestFuzz_SponsorshipPaymasterWithPremium is NexusTestBase {
    BiconomySponsorshipPaymaster public bicoPaymaster;

    function setUp() public {
        setupTestEnvironment();
        // Deploy Sponsorship Paymaster
        bicoPaymaster = new BiconomySponsorshipPaymaster(
            PAYMASTER_OWNER.addr, ENTRYPOINT, PAYMASTER_SIGNER.addr, PAYMASTER_FEE_COLLECTOR.addr
        );
    }

    function testFuzz_DepositFor(uint256 depositAmount) external {
        vm.assume(depositAmount <= 1000 ether);
        vm.assume(depositAmount > 0 ether);
        vm.deal(DAPP_ACCOUNT.addr, depositAmount);

        uint256 dappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        assertEq(dappPaymasterBalance, 0 ether);

        vm.expectEmit(true, true, false, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasDeposited(DAPP_ACCOUNT.addr, depositAmount);
        bicoPaymaster.depositFor{ value: depositAmount }(DAPP_ACCOUNT.addr);

        dappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        assertEq(dappPaymasterBalance, depositAmount);
    }

    function testFuzz_WithdrawTo(uint256 withdrawAmount) external prankModifier(DAPP_ACCOUNT.addr) {
        vm.assume(withdrawAmount <= 1000 ether);
        vm.assume(withdrawAmount > 0 ether);
        vm.deal(DAPP_ACCOUNT.addr, withdrawAmount);

        bicoPaymaster.depositFor{ value: withdrawAmount }(DAPP_ACCOUNT.addr);
        uint256 danInitialBalance = DAN_ADDRESS.balance;

        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasWithdrawn(DAPP_ACCOUNT.addr, DAN_ADDRESS, withdrawAmount);
        bicoPaymaster.withdrawTo(payable(DAN_ADDRESS), withdrawAmount);

        uint256 dappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        assertEq(dappPaymasterBalance, 0 ether);
        uint256 expectedDanBalance = danInitialBalance + withdrawAmount;
        assertEq(DAN_ADDRESS.balance, expectedDanBalance);
    }

    function testFuzz_Receive(uint256 ethAmount) external prankModifier(ALICE_ADDRESS) {
        vm.assume(ethAmount <= 1000 ether);
        vm.assume(ethAmount > 0 ether);
        uint256 initialPaymasterBalance = address(bicoPaymaster).balance;

        vm.expectEmit(true, true, false, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.Received(ALICE_ADDRESS, ethAmount);
        (bool success,) = address(bicoPaymaster).call{ value: ethAmount }("");

        assert(success);
        uint256 resultingPaymasterBalance = address(bicoPaymaster).balance;
        assertEq(resultingPaymasterBalance, initialPaymasterBalance + ethAmount);
    }

    function testFuzz_WithdrawEth(uint256 ethAmount) external prankModifier(PAYMASTER_OWNER.addr) {
        vm.assume(ethAmount <= 1000 ether);
        vm.assume(ethAmount > 0 ether);
        vm.deal(address(bicoPaymaster), ethAmount);
        uint256 initialAliceBalance = ALICE_ADDRESS.balance;

        bicoPaymaster.withdrawEth(payable(ALICE_ADDRESS), ethAmount);

        assertEq(ALICE_ADDRESS.balance, initialAliceBalance + ethAmount);
        assertEq(address(bicoPaymaster).balance, 0 ether);
    }

    function testFuzz_WithdrawErc20(address target, uint256 amount) external prankModifier(PAYMASTER_OWNER.addr) {
        vm.assume(target != address(0));
        vm.assume(amount <= 1_000_000 * (10 ** 18));
        MockToken token = new MockToken("Token", "TKN");
        uint256 mintAmount = amount;
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

    function testFuzz_ValidatePaymasterAndPostOpWithPremium(uint32 premium) external {
        vm.assume(premium <= 2e6);
        vm.assume(premium > 1e6);

        uint256 initialDappPaymasterBalance = 10 ether;
        bicoPaymaster.depositFor{ value: initialDappPaymasterBalance }(DAPP_ACCOUNT.addr);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);

        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));

        userOp.paymasterAndData = generateAndSignPaymasterData(
            userOp, PAYMASTER_SIGNER, bicoPaymaster, 3e6, 3e6, DAPP_ACCOUNT.addr, validUntil, validAfter, premium
        );
        userOp.signature = signUserOp(ALICE, userOp);

        // Estimate paymaster gas limits
        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOp);
        (uint256 validationGasLimit, uint256 postopGasLimit) =
            estimatePaymasterGasCosts(bicoPaymaster, userOp, userOpHash, 5e4);

        // Ammend the userop to have new gas limits and signature
        userOp.paymasterAndData = generateAndSignPaymasterData(
            userOp,
            PAYMASTER_SIGNER,
            bicoPaymaster,
            uint128(validationGasLimit),
            uint128(postopGasLimit),
            DAPP_ACCOUNT.addr,
            validUntil,
            validAfter,
            premium
        );
        userOp.signature = signUserOp(ALICE, userOp);
        ops[0] = userOp;
        userOpHash = ENTRYPOINT.getUserOpHash(userOp);

        uint256 initialFeeCollectorBalance = bicoPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr);
        initialDappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        vm.expectEmit(true, false, false, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.PremiumCollected(DAPP_ACCOUNT.addr, 0);
        vm.expectEmit(true, false, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasBalanceDeducted(DAPP_ACCOUNT.addr, 0, userOpHash);
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));

        uint256 resultingDappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        uint256 resultingFeeCollectorPaymasterBalance = bicoPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr);

        uint256 totalGasFeesCharged = initialDappPaymasterBalance - resultingDappPaymasterBalance;

        uint256 premiumCollected = resultingFeeCollectorPaymasterBalance - initialFeeCollectorBalance;
        uint256 expectedPremium = totalGasFeesCharged - ((totalGasFeesCharged * 1e6) / premium);

        assertEq(premiumCollected, expectedPremium);
    }
}
