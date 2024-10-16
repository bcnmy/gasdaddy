// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.27;

import "../../base/TestBase.sol";
import { IBiconomySponsorshipPaymaster } from "../../../contracts/interfaces/IBiconomySponsorshipPaymaster.sol";
import { BiconomySponsorshipPaymaster } from "../../../contracts/sponsorship/BiconomySponsorshipPaymaster.sol";
import { MockToken } from "@nexus/contracts/mocks/MockToken.sol";

contract TestFuzz_SponsorshipPaymasterWithPriceMarkup is TestBase {
    BiconomySponsorshipPaymaster public bicoPaymaster;

    function setUp() public {
        setupPaymasterTestEnvironment();
        // Deploy Sponsorship Paymaster
        bicoPaymaster = new BiconomySponsorshipPaymaster(
            PAYMASTER_OWNER.addr, ENTRYPOINT, PAYMASTER_SIGNER.addr, PAYMASTER_FEE_COLLECTOR.addr, 7e3
        );
    }

    function testFuzz_DepositFor(uint256 depositAmount) external {
        vm.assume(depositAmount <= 1000 ether && depositAmount > 0 ether);
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
        vm.assume(withdrawAmount <= 1000 ether && withdrawAmount > 0 ether);
        vm.deal(DAPP_ACCOUNT.addr, withdrawAmount);

        bicoPaymaster.depositFor{ value: withdrawAmount }(DAPP_ACCOUNT.addr);
        uint256 danInitialBalance = BOB_ADDRESS.balance;

        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasWithdrawn(DAPP_ACCOUNT.addr, BOB_ADDRESS, withdrawAmount);
        bicoPaymaster.withdrawTo(payable(BOB_ADDRESS), withdrawAmount);

        uint256 dappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        assertEq(dappPaymasterBalance, 0 ether);
        uint256 expectedDanBalance = danInitialBalance + withdrawAmount;
        assertEq(BOB_ADDRESS.balance, expectedDanBalance);
    }

    function testFuzz_Receive(uint256 ethAmount) external prankModifier(ALICE_ADDRESS) {
        vm.assume(ethAmount <= 1000 ether && ethAmount > 0 ether);
        uint256 initialPaymasterBalance = address(bicoPaymaster).balance;

        vm.expectEmit(true, true, false, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.Received(ALICE_ADDRESS, ethAmount);
        (bool success,) = address(bicoPaymaster).call{ value: ethAmount }("");

        assert(success);
        uint256 resultingPaymasterBalance = address(bicoPaymaster).balance;
        assertEq(resultingPaymasterBalance, initialPaymasterBalance + ethAmount);
    }

    function testFuzz_WithdrawEth(uint256 ethAmount) external prankModifier(PAYMASTER_OWNER.addr) {
        vm.assume(ethAmount <= 1000 ether && ethAmount > 0 ether);
        vm.deal(address(bicoPaymaster), ethAmount);
        uint256 initialAliceBalance = ALICE_ADDRESS.balance;

        bicoPaymaster.withdrawEth(payable(ALICE_ADDRESS), ethAmount);

        assertEq(ALICE_ADDRESS.balance, initialAliceBalance + ethAmount);
        assertEq(address(bicoPaymaster).balance, 0 ether);
    }

    function testFuzz_WithdrawErc20(address target, uint256 amount) external prankModifier(PAYMASTER_OWNER.addr) {
        vm.assume(target != address(0) && amount <= 1_000_000 * (10 ** 18));
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

    function skip_testFuzz_ValidatePaymasterAndPostOpWithPriceMarkup(uint32 priceMarkup) external {
        vm.assume(priceMarkup <= 2e6 && priceMarkup > 1e6);
        bicoPaymaster.depositFor{ value: 10 ether }(DAPP_ACCOUNT.addr);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        (PackedUserOperation memory userOp, bytes32 userOpHash) = createUserOp(ALICE, bicoPaymaster, priceMarkup);
        ops[0] = userOp;

        uint256 initialBundlerBalance = BUNDLER.addr.balance;
        uint256 initialPaymasterEpBalance = bicoPaymaster.getDeposit();
        uint256 initialDappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        uint256 initialFeeCollectorBalance = bicoPaymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr);

        vm.expectEmit(true, false, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasBalanceDeducted(DAPP_ACCOUNT.addr, 0, 0, userOpHash);
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));

        // Calculate and assert price markups and gas payments
        calculateAndAssertAdjustments(
            bicoPaymaster,
            initialDappPaymasterBalance,
            initialFeeCollectorBalance,
            initialBundlerBalance,
            initialPaymasterEpBalance,
            priceMarkup
        );
    }

    function testFuzz_ParsePaymasterAndData(
        address paymasterId,
        uint48 validUntil,
        uint48 validAfter,
        uint32 priceMarkup
    )
        external
        view
    {
        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));
        (bytes memory paymasterAndData, bytes memory signature) = generateAndSignPaymasterData(
            userOp, PAYMASTER_SIGNER, bicoPaymaster, 3e6, 3e6, paymasterId, validUntil, validAfter, priceMarkup
        );

        (
            address parsedPaymasterId,
            uint48 parsedValidUntil,
            uint48 parsedValidAfter,
            uint32 parsedPriceMarkup,
            bytes memory parsedSignature
        ) = bicoPaymaster.parsePaymasterAndData(paymasterAndData);

        assertEq(paymasterId, parsedPaymasterId);
        assertEq(validUntil, parsedValidUntil);
        assertEq(validAfter, parsedValidAfter);
        assertEq(priceMarkup, parsedPriceMarkup);
        assertEq(signature, parsedSignature);
    }
}
