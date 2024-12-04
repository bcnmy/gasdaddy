// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.27;

import { TokenPaymasterParserLib } from "../../contracts/libraries/TokenPaymasterParserLib.sol";
import { IBiconomyTokenPaymaster } from "../../contracts/interfaces/IBiconomyTokenPaymaster.sol";

library PaymasterParserLibExposed {
    using TokenPaymasterParserLib for bytes;

    function parsePaymasterAndData(bytes calldata paymasterAndData) public pure returns (IBiconomyTokenPaymaster.PaymasterMode mode, bytes calldata modeSpecificData) {
        return paymasterAndData.parsePaymasterAndData();
    }

    function parseExternalModeSpecificData(bytes calldata modeSpecificData) public pure returns (
            uint48 validUntil,
            uint48 validAfter,
            address tokenAddress,
            uint256 estimatedTokenAmount, 
            bytes calldata signature
        ) {
        return modeSpecificData.parseExternalModeSpecificData();
    }

    function parseIndependentModeSpecificData(bytes calldata modeSpecificData) public pure returns (address tokenAddress) {
        return modeSpecificData.parseIndependentModeSpecificData();
    }
}