// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.27;

import { PaymasterParserLibExposed } from "./PaymasterParserLibExposed.sol";
import { IBiconomyTokenPaymaster } from "../../contracts/interfaces/IBiconomyTokenPaymaster.sol";

contract PaymasterParserLibWrapper {
    using PaymasterParserLibExposed for bytes;

    function parsePaymasterAndData(bytes calldata paymasterAndData) external pure returns (IBiconomyTokenPaymaster.PaymasterMode mode, bytes memory modeSpecificData) {
        (mode, modeSpecificData) = paymasterAndData.parsePaymasterAndData();
    }

    function parseExternalModeSpecificData(bytes calldata modeSpecificData) external pure returns (
            uint48 validUntil,
            uint48 validAfter,
            address tokenAddress,
            uint256 estimatedTokenAmount, 
            bytes memory signature
        ) {
        (validUntil, validAfter, tokenAddress, estimatedTokenAmount, signature) = modeSpecificData.parseExternalModeSpecificData();
    }

    function parseIndependentModeSpecificData(bytes calldata modeSpecificData) external pure returns (address tokenAddress) {
        tokenAddress = modeSpecificData.parseIndependentModeSpecificData();
    }
}