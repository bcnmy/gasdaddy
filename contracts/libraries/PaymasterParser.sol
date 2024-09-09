// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import { IBiconomyTokenPaymaster } from "../interfaces/IBiconomyTokenPaymaster.sol";
import "@account-abstraction/contracts/core/UserOperationLib.sol";

// A helper library to parse paymaster and data
library PaymasterParser {
    uint256 private constant PAYMASTER_MODE_OFFSET = UserOperationLib.PAYMASTER_DATA_OFFSET; // Start offset of mode in
        // PND

    function parsePaymasterAndData(bytes calldata paymasterAndData)
        external
        pure
        returns (IBiconomyTokenPaymaster.PaymasterMode mode, bytes memory modeSpecificData)
    {
        unchecked {
            mode = IBiconomyTokenPaymaster.PaymasterMode(
                uint8(bytes1(paymasterAndData[PAYMASTER_MODE_OFFSET:PAYMASTER_MODE_OFFSET + 8]))
            );
            modeSpecificData = paymasterAndData[PAYMASTER_MODE_OFFSET + 8:];
        }
    }

    function parseExternalModeSpecificData(bytes calldata modeSpecificData) external pure { }

    function parseIndependentModeSpecificData(bytes calldata modeSpecificData)
        external
        pure
        returns (address tokenAddress)
    {
        tokenAddress = address(bytes20(modeSpecificData[:20]));
    }
}
