// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import { IStakeManager } from "account-abstraction/interfaces/IStakeManager.sol";

interface IBiconomyTokenPaymasterWithdraw {
    function withdrawTo(address to, uint256 amount) external;
}

contract WithdrawDeposit is Script {

    address constant PAYMASTER_ADDRESS = 0x00000054bbe1c7aEFB16E7cc9Be4f5ebd7e88361;
    address constant WITHDRAW_ADDRESS = 0x531b827c1221EC7CE13266e8F5CB1ec6Ae470be5;
    address constant ENTRYPOINT_ADDRESS = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() public {
        IBiconomyTokenPaymasterWithdraw paymaster = IBiconomyTokenPaymasterWithdraw(PAYMASTER_ADDRESS);
        IStakeManager stakeManager = IStakeManager(ENTRYPOINT_ADDRESS);

        uint256 balance = stakeManager.getDepositInfo(PAYMASTER_ADDRESS).deposit;
        console.log("Balance of", PAYMASTER_ADDRESS, "is", balance);
        vm.startBroadcast();
        paymaster.withdrawTo(WITHDRAW_ADDRESS, balance);
        vm.stopBroadcast();
    }
}

// USAGE: forge script WithdrawDeposit --rpc-url ___ --private-key $MAINNET_DEPLOYER_PRIVATE_KEY --broadcast

