// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/src/Test.sol";

import { EntryPoint } from "account-abstraction/contracts/core/EntryPoint.sol";
import { Nexus } from "@nexus/contracts/Nexus.sol";
import { NexusAccountFactory } from "@nexus/contracts/factory/NexusAccountFactory.sol";

abstract contract NexusTestBase is Test {
    // Test Environment Configuration
    string constant mnemonic = "test test test test test test test test test test test junk";
    uint256 constant testAccountCount = 10;
    uint256 constant initialMainAccountFunds = 100_000 ether;
    uint256 constant defaultPreVerificationGas = 21_000;

    uint32 nextKeyIndex;

    // Test Accounts
    struct TestAccount {
        address payable addr;
        uint256 privateKey;
    }

    TestAccount[] testAccounts;
    TestAccount alice;
    TestAccount bob;
    TestAccount charlie;
    TestAccount dan;
    TestAccount emma;
    TestAccount frank;
    TestAccount george;
    TestAccount henry;
    TestAccount ida;

    TestAccount owner;

    // ERC7579 Contracts
    EntryPoint entryPoint;
    Nexus saImplementation;
    NexusAccountFactory factory;

    function getNextPrivateKey() internal returns (uint256) {
        return vm.deriveKey(mnemonic, ++nextKeyIndex);
    }

    function setUp() public virtual {
        // Generate Test Addresses
        for (uint256 i = 0; i < testAccountCount; i++) {
            uint256 privateKey = getNextPrivateKey();
            testAccounts.push(TestAccount(payable(vm.addr(privateKey)), privateKey));

            deal(testAccounts[i].addr, initialMainAccountFunds);
        }

        // Name Test Addresses
        alice = testAccounts[0];
        vm.label(alice.addr, string.concat("Alice", vm.toString(uint256(0))));

        bob = testAccounts[1];
        vm.label(bob.addr, string.concat("Bob", vm.toString(uint256(1))));

        charlie = testAccounts[2];
        vm.label(charlie.addr, string.concat("Charlie", vm.toString(uint256(2))));

        dan = testAccounts[3];
        vm.label(dan.addr, string.concat("Dan", vm.toString(uint256(3))));

        emma = testAccounts[4];
        vm.label(emma.addr, string.concat("Emma", vm.toString(uint256(4))));

        frank = testAccounts[5];
        vm.label(frank.addr, string.concat("Frank", vm.toString(uint256(5))));

        george = testAccounts[6];
        vm.label(george.addr, string.concat("George", vm.toString(uint256(6))));

        henry = testAccounts[7];
        vm.label(henry.addr, string.concat("Henry", vm.toString(uint256(7))));

        ida = testAccounts[7];
        vm.label(ida.addr, string.concat("Ida", vm.toString(uint256(8))));

        // Name Owner
        owner = testAccounts[8];
        vm.label(owner.addr, string.concat("Owner", vm.toString(uint256(9))));
    }
}
