// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { IBiconomyTokenPaymaster } from "../interfaces/IBiconomyTokenPaymaster.sol";
import "account-abstraction/core/UserOperationLib.sol";

// A helper library to parse paymaster and data
library TokenPaymasterParserLib {
    // Start offset of mode in PND
    uint256 private constant PAYMASTER_MODE_OFFSET = UserOperationLib.PAYMASTER_DATA_OFFSET;

    function parsePaymasterAndData(
        bytes calldata paymasterAndData
    )
        external
        pure
        returns (IBiconomyTokenPaymaster.PaymasterMode mode, bytes memory modeSpecificData)
    {
        unchecked {
            mode = IBiconomyTokenPaymaster.PaymasterMode(uint8(bytes1(paymasterAndData[PAYMASTER_MODE_OFFSET])));
            modeSpecificData = paymasterAndData[PAYMASTER_MODE_OFFSET + 1:];
        }
    }

    function parseExternalModeSpecificData(
        bytes calldata modeSpecificData
    )
        external
        pure
        returns (
            uint48 validUntil,
            uint48 validAfter,
            address tokenAddress,
            uint128 tokenPrice,
            uint32 externalPriceMarkup,
            bytes memory signature
        )
    {
        validUntil = uint48(bytes6(modeSpecificData[:6]));
        validAfter = uint48(bytes6(modeSpecificData[6:12]));
        tokenAddress = address(bytes20(modeSpecificData[12:32]));
        tokenPrice = uint128(bytes16(modeSpecificData[32:48]));
        externalPriceMarkup = uint32(bytes4(modeSpecificData[48:52]));
        signature = modeSpecificData[52:];
    }

    function parseIndependentModeSpecificData(
        bytes calldata modeSpecificData
    )
        external
        pure
        returns (address tokenAddress)
    {
        tokenAddress = address(bytes20(modeSpecificData[:20]));
    }
}
