// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.26;

import { console2 } from "forge-std/src/Console2.sol";
import { NexusTestBase } from "../../base/NexusTestBase.sol";
import { IBiconomySponsorshipPaymaster } from "../../../../contracts/interfaces/IBiconomySponsorshipPaymaster.sol";
import { BiconomySponsorshipPaymaster } from "../../../../contracts/sponsorship/SponsorshipPaymasterWithPremium.sol";

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

    function testFuzz_WithdrawTo(uint256 withdrawAmount) external {
        vm.assume(withdrawAmount <= 1000 ether);
        vm.assume(withdrawAmount > 0 ether);
        vm.deal(DAPP_ACCOUNT.addr, withdrawAmount);
        bicoPaymaster.depositFor{ value: withdrawAmount }(DAPP_ACCOUNT.addr);
        uint256 danInitialBalance = DAN_ADDRESS.balance;

        vm.startPrank(DAPP_ACCOUNT.addr);
        vm.expectEmit(true, true, true, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.GasWithdrawn(DAPP_ACCOUNT.addr, DAN_ADDRESS, withdrawAmount);
        bicoPaymaster.withdrawTo(payable(DAN_ADDRESS), withdrawAmount);
        uint256 dappPaymasterBalance = bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);
        assertEq(dappPaymasterBalance, 0 ether);
        uint256 expectedDanBalance = danInitialBalance + withdrawAmount;
        assertEq(DAN_ADDRESS.balance, expectedDanBalance);
        vm.stopPrank();
    }

    function testFuzz_Receive(uint256 ethAmount) external {
        vm.assume(ethAmount <= 1000 ether);
        vm.assume(ethAmount > 0 ether);
        uint256 initialPaymasterBalance = address(bicoPaymaster).balance;
        vm.startPrank(ALICE_ADDRESS);
        vm.expectEmit(true, true, false, true, address(bicoPaymaster));
        emit IBiconomySponsorshipPaymaster.Received(ALICE_ADDRESS, ethAmount);
        (bool success,) = address(bicoPaymaster).call{ value: ethAmount }("");
        vm.stopPrank();
        assert(success);
        uint256 resultingPaymasterBalance = address(bicoPaymaster).balance;
        assertEq(resultingPaymasterBalance, initialPaymasterBalance + ethAmount);
    }

    function testFuzz_WithdrawEth(uint256 ethAmount) external {
        vm.assume(ethAmount <= 1000 ether);
        vm.assume(ethAmount > 0 ether);
        uint256 initialAliceBalance = ALICE_ADDRESS.balance;
        vm.deal(address(bicoPaymaster), ethAmount);
        vm.startPrank(PAYMASTER_OWNER.addr);
        bicoPaymaster.withdrawEth(payable(ALICE_ADDRESS), ethAmount);
        vm.stopPrank();
        assertEq(ALICE_ADDRESS.balance, initialAliceBalance + ethAmount);
        assertEq(address(bicoPaymaster).balance, 0 ether);
    }
}
