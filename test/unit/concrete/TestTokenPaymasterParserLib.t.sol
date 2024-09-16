// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.26;

import "lib/forge-std/src/Test.sol";
import "../../../contracts/libraries/TokenPaymasterParserLib.sol";
import { IBiconomyTokenPaymaster } from "../../../contracts/interfaces/IBiconomyTokenPaymaster.sol";

// Mock contract to test the TokenPaymasterParserLib
contract TestTokenPaymasterParserLib is Test {
    using TokenPaymasterParserLib for bytes;

    function test_ParsePaymasterAndData_ExternalMode() public {
        // Simulate an example paymasterAndData for External Mode
        IBiconomyTokenPaymaster.PaymasterMode expectedMode = IBiconomyTokenPaymaster.PaymasterMode.EXTERNAL;

        // Encode the mode (0 for EXTERNAL)
        bytes memory modeSpecificData = hex"000102030405060708091011121314151617181920212223242526";

        // The PAYMASTER_MODE_OFFSET must be accounted for by placing the mode at the correct offset
        bytes memory paymasterAndData = abi.encodePacked(
            address(this),
            uint128(1e6), // Example gas value
            uint128(1e6),
            uint8(expectedMode), // Mode (0 for EXTERNAL)
            modeSpecificData // Mode specific data
        );

        // Parse the paymasterAndData
        (IBiconomyTokenPaymaster.PaymasterMode parsedMode, bytes memory parsedModeSpecificData) =
            paymasterAndData.parsePaymasterAndData();

        // Validate the mode and modeSpecificData
        assertEq(uint8(parsedMode), uint8(expectedMode), "Mode should match External");
        assertEq(parsedModeSpecificData, modeSpecificData, "Mode specific data should match");
    }

    function test_ParsePaymasterAndData_IndependentMode() public {
        // Simulate an example paymasterAndData for Independent Mode
        IBiconomyTokenPaymaster.PaymasterMode expectedMode = IBiconomyTokenPaymaster.PaymasterMode.INDEPENDENT;

        // Encode the mode (1 for INDEPENDENT)
        bytes memory modeSpecificData = hex"11223344556677889900aabbccddeeff";

        // The PAYMASTER_MODE_OFFSET must be accounted for by placing the mode at the correct offset
        bytes memory paymasterAndData = abi.encodePacked(
            address(this),
            uint128(1e6), // Example gas value
            uint128(1e6),
            uint8(expectedMode), // Mode (1 for INDEPENDENT)
            modeSpecificData // Mode specific data
        );

        // Parse the paymasterAndData
        (IBiconomyTokenPaymaster.PaymasterMode parsedMode, bytes memory parsedModeSpecificData) =
            paymasterAndData.parsePaymasterAndData();

        // Validate the mode and modeSpecificData
        assertEq(uint8(parsedMode), uint8(expectedMode), "Mode should match Independent");
        assertEq(parsedModeSpecificData, modeSpecificData, "Mode specific data should match");
    }

    function test_ParseExternalModeSpecificData() public view {
        // Simulate valid external mode specific data
        uint48 expectedValidUntil = uint48(block.timestamp + 1 days);
        uint48 expectedValidAfter = uint48(block.timestamp);
        address expectedTokenAddress = address(0x1234567890AbcdEF1234567890aBcdef12345678);
        uint128 expectedTokenPrice = 1e8;
        uint32 expectedExternalPriceMarkup = 1e6;
        bytes memory expectedSignature = hex"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef";

        // Construct external mode specific data
        bytes memory externalModeSpecificData = abi.encodePacked(
            bytes6(abi.encodePacked(expectedValidUntil)),
            bytes6(abi.encodePacked(expectedValidAfter)),
            bytes20(expectedTokenAddress),
            bytes16(abi.encodePacked(expectedTokenPrice)),
            bytes4(abi.encodePacked(expectedExternalPriceMarkup)),
            expectedSignature
        );

        // Parse the mode specific data
        (
            uint48 parsedValidUntil,
            uint48 parsedValidAfter,
            address parsedTokenAddress,
            uint128 parsedTokenPrice,
            uint32 parsedExternalPriceMarkup,
            bytes memory parsedSignature
        ) = externalModeSpecificData.parseExternalModeSpecificData();

        // Validate the parsed values
        assertEq(parsedValidUntil, expectedValidUntil, "ValidUntil should match");
        assertEq(parsedValidAfter, expectedValidAfter, "ValidAfter should match");
        assertEq(parsedTokenAddress, expectedTokenAddress, "Token address should match");
        assertEq(parsedTokenPrice, expectedTokenPrice, "Token price should match");
        assertEq(parsedExternalPriceMarkup, expectedExternalPriceMarkup, "Dynamic adjustment should match");
        assertEq(parsedSignature, expectedSignature, "Signature should match");
    }

    function test_ParseIndependentModeSpecificData() public pure {
        // Simulate valid independent mode specific data
        address expectedTokenAddress = address(0x9876543210AbCDef9876543210ABCdEf98765432);
        bytes memory independentModeSpecificData = abi.encodePacked(bytes20(expectedTokenAddress));

        // Parse the mode specific data
        address parsedTokenAddress = independentModeSpecificData.parseIndependentModeSpecificData();

        // Validate the parsed token address
        assertEq(parsedTokenAddress, expectedTokenAddress, "Token address should match");
    }

    function test_RevertIf_InvalidExternalModeSpecificDataLength() public {
        // Simulate invalid external mode specific data (incorrect length)
        bytes memory invalidExternalModeSpecificData = hex"0001020304050607";

        // Expect the test to revert due to invalid data length
        vm.expectRevert();
        invalidExternalModeSpecificData.parseExternalModeSpecificData();
    }

    function test_RevertIf_InvalidIndependentModeSpecificDataLength() public {
        // Simulate invalid independent mode specific data (incorrect length)
        bytes memory invalidIndependentModeSpecificData = hex"00010203";

        // Expect the test to revert due to invalid data length
        vm.expectRevert();
        invalidIndependentModeSpecificData.parseIndependentModeSpecificData();
    }
}
