// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";

import "solady/utils/ECDSA.sol";
import "./TestHelper.sol";

import { IAccount } from "account-abstraction/interfaces/IAccount.sol";
import { Exec } from "account-abstraction/utils/Exec.sol";
import { IPaymaster } from "account-abstraction/interfaces/IPaymaster.sol";

import { Nexus } from "@nexus/contracts/Nexus.sol";
import { CheatCodes } from "@nexus/test/foundry/utils/CheatCodes.sol";
import { BaseEventsAndErrors } from "./BaseEventsAndErrors.sol";

import { BiconomySponsorshipPaymaster } from "../../contracts/sponsorship/BiconomySponsorshipPaymaster.sol";

import {
    BiconomyTokenPaymaster,
    IBiconomyTokenPaymaster,
    BiconomyTokenPaymasterErrors,
    IOracle
} from "../../../contracts/token/BiconomyTokenPaymaster.sol";

abstract contract TestBase is CheatCodes, TestHelper, BaseEventsAndErrors {
    address constant ENTRYPOINT_ADDRESS = address(0x0000000071727De22E5E9d8BAf0edAc6f37da032);

    address constant WRAPPED_NATIVE_ADDRESS = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address constant SWAP_ROUTER_ADDRESS = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    Vm.Wallet internal PAYMASTER_OWNER;
    Vm.Wallet internal PAYMASTER_SIGNER;
    Vm.Wallet internal PAYMASTER_FEE_COLLECTOR;
    Vm.Wallet internal DAPP_ACCOUNT;

    // Used to buffer user op gas limits
    // GAS_LIMIT = (ESTIMATED_GAS * GAS_BUFFER_RATIO) / 100
    uint8 private constant GAS_BUFFER_RATIO = 110;

    // -----------------------------------------
    // Modifiers
    // -----------------------------------------
    modifier prankModifier(address pranker) {
        startPrank(pranker);
        _;
        stopPrank();
    }

    // -----------------------------------------
    // Setup Functions
    // -----------------------------------------
    /// @notice Initializes the testing environment with wallets, contracts, and accounts
    function setupPaymasterTestEnvironment() internal virtual {
        /// Initializes the testing environment
        setupPredefinedWallets();
        setupPaymasterPredefinedWallets();
        deployTestContracts();
        deployNexusForPredefinedWallets();
    }

    function setupPaymasterPredefinedWallets() internal {
        PAYMASTER_OWNER = createAndFundWallet("PAYMASTER_OWNER", 1000 ether);
        PAYMASTER_SIGNER = createAndFundWallet("PAYMASTER_SIGNER", 1000 ether);
        PAYMASTER_FEE_COLLECTOR = createAndFundWallet("PAYMASTER_FEE_COLLECTOR", 1000 ether);
        DAPP_ACCOUNT = createAndFundWallet("DAPP_ACCOUNT", 1000 ether);
        FACTORY_OWNER = createAndFundWallet("FACTORY_OWNER", 1000 ether);
    }

    function estimateUserOpGasCosts(
        PackedUserOperation memory userOp
    )
        internal
        prankModifier(ENTRYPOINT_ADDRESS)
        returns (uint256 verificationGasUsed, uint256 callGasUsed, uint256 verificationGasLimit, uint256 callGasLimit)
    {
        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOp);
        verificationGasUsed = gasleft();
        IAccount(userOp.sender).validateUserOp(userOp, userOpHash, 0);
        verificationGasUsed = verificationGasUsed - gasleft();

        callGasUsed = gasleft();
        bool success = Exec.call(userOp.sender, 0, userOp.callData, 3e6);
        callGasUsed = callGasUsed - gasleft();
        assert(success);

        verificationGasLimit = (verificationGasUsed * GAS_BUFFER_RATIO) / 100;
        callGasLimit = (callGasUsed * GAS_BUFFER_RATIO) / 100;
    }

    function estimatePaymasterGasCosts(
        BiconomySponsorshipPaymaster paymaster,
        PackedUserOperation memory userOp,
        uint256 requiredPreFund
    )
        internal
        prankModifier(ENTRYPOINT_ADDRESS)
        returns (uint256 validationGasUsed, uint256 postopGasUsed, uint256 validationGasLimit, uint256 postopGasLimit)
    {
        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOp);
        // Warm up accounts to get more accurate gas estimations
        (bytes memory context,) = paymaster.validatePaymasterUserOp(userOp, userOpHash, requiredPreFund);
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, 1e12, 3e6);

        // Estimate gas used
        validationGasUsed = gasleft();
        (context,) = paymaster.validatePaymasterUserOp(userOp, userOpHash, requiredPreFund);
        validationGasUsed = validationGasUsed - gasleft();

        postopGasUsed = gasleft();
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, 1e12, 3e6);
        postopGasUsed = (postopGasUsed - gasleft());

        validationGasLimit = (validationGasUsed * GAS_BUFFER_RATIO) / 100;
        postopGasLimit = (postopGasUsed * GAS_BUFFER_RATIO) / 100;
    }

    function createUserOp(
        Vm.Wallet memory sender,
        BiconomySponsorshipPaymaster paymaster,
        uint32 priceMarkup
    )
        internal
        returns (PackedUserOperation memory userOp, bytes32 userOpHash)
    {
        // Create userOp with no gas estimates
        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);

        userOp = buildUserOpWithCalldata(sender, "", address(VALIDATOR_MODULE));

        (userOp.paymasterAndData,) = generateAndSignPaymasterData(
            userOp, PAYMASTER_SIGNER, paymaster, 3e6, 8e3, DAPP_ACCOUNT.addr, validUntil, validAfter, priceMarkup
        );
        userOp.signature = signUserOp(sender, userOp);

        (,, uint256 verificationGasLimit, uint256 callGasLimit) = estimateUserOpGasCosts(userOp);
        // Estimate paymaster gas limits
        (, uint256 postopGasUsed, uint256 validationGasLimit, uint256 postopGasLimit) =
            estimatePaymasterGasCosts(paymaster, userOp, 5e4);

        // console2.log("postOpGasUsed");
        // console2.logUint(postopGasUsed);

        // uint256 prevValUnaccountedGas = paymaster.unaccountedGas();
        // console2.logUint(prevValUnaccountedGas);

        // Below may not be needed if unaccountedGas is set correctly
        vm.startPrank(paymaster.owner());
        // Set unaccounted gas to be gas used in postop + 1000 for EP overhead and penalty
        paymaster.setUnaccountedGas(postopGasUsed + 500);
        vm.stopPrank();

        // uint256 currentValUnaccountedGas = paymaster.unaccountedGas();
        // console2.logUint(currentValUnaccountedGas);

        // Ammend the userop to have new gas limits and signature
        userOp.accountGasLimits = bytes32(abi.encodePacked(uint128(verificationGasLimit), uint128(callGasLimit)));
        (userOp.paymasterAndData,) = generateAndSignPaymasterData(
            userOp,
            PAYMASTER_SIGNER,
            paymaster,
            uint128(validationGasLimit),
            uint128(postopGasLimit),
            DAPP_ACCOUNT.addr,
            validUntil,
            validAfter,
            priceMarkup
        );
        userOp.signature = signUserOp(sender, userOp);
        userOpHash = ENTRYPOINT.getUserOpHash(userOp);
    }

    /// @notice Generates and signs the paymaster data for a user operation.
    /// @dev This function prepares the `paymasterAndData` field for a `PackedUserOperation` with the correct signature.
    /// @param userOp The user operation to be signed.
    /// @param signer The wallet that will sign the paymaster hash.
    /// @param paymaster The paymaster contract.
    /// @return finalPmData Full Pm Data.
    /// @return signature  Pm Signature on Data.
    function generateAndSignPaymasterData(
        PackedUserOperation memory userOp,
        Vm.Wallet memory signer,
        BiconomySponsorshipPaymaster paymaster,
        uint128 paymasterValGasLimit,
        uint128 paymasterPostOpGasLimit,
        address paymasterId,
        uint48 validUntil,
        uint48 validAfter,
        uint32 priceMarkup
    )
        internal
        view
        returns (bytes memory finalPmData, bytes memory signature)
    {
        // Initial paymaster data with zero signature
        bytes memory initialPmData = abi.encodePacked(
            address(paymaster),
            paymasterValGasLimit,
            paymasterPostOpGasLimit,
            paymasterId,
            validUntil,
            validAfter,
            priceMarkup,
            new bytes(65) // Zero signature
        );

        // Update user operation with initial paymaster data
        userOp.paymasterAndData = initialPmData;

        // Generate hash to be signed
        bytes32 paymasterHash = paymaster.getHash(userOp, paymasterId, validUntil, validAfter, priceMarkup);

        // Sign the hash
        signature = signMessage(signer, paymasterHash);
        require(signature.length == 65, "Invalid Paymaster Signature length");

        // Final paymaster data with the actual signature
        finalPmData = abi.encodePacked(
            address(paymaster),
            paymasterValGasLimit,
            paymasterPostOpGasLimit,
            paymasterId,
            validUntil,
            validAfter,
            priceMarkup,
            signature
        );
    }

    /// @notice Generates and signs the paymaster data for a user operation.
    /// @dev This function prepares the `paymasterAndData` field for a `PackedUserOperation` with the correct signature.
    /// @param userOp The user operation to be signed.
    /// @param signer The wallet that will sign the paymaster hash.
    /// @param paymaster The paymaster contract.
    /// @return finalPmData Full Pm Data.
    /// @return signature  Pm Signature on Data.
    function generateAndSignTokenPaymasterData(
        PackedUserOperation memory userOp,
        Vm.Wallet memory signer,
        BiconomyTokenPaymaster paymaster,
        uint128 paymasterValGasLimit,
        uint128 paymasterPostOpGasLimit,
        IBiconomyTokenPaymaster.PaymasterMode mode,
        uint48 validUntil,
        uint48 validAfter,
        address tokenAddress,
        uint128 tokenPrice,
        uint32 externalPriceMarkup
    )
        internal
        view
        returns (bytes memory finalPmData, bytes memory signature)
    {
        // Initial paymaster data with zero signature
        bytes memory initialPmData = abi.encodePacked(
            address(paymaster),
            paymasterValGasLimit,
            paymasterPostOpGasLimit,
            uint8(mode),
            validUntil,
            validAfter,
            tokenAddress,
            tokenPrice,
            externalPriceMarkup,
            new bytes(65) // Zero signature
        );

        // Update user operation with initial paymaster data
        userOp.paymasterAndData = initialPmData;

        // Generate hash to be signed
        bytes32 paymasterHash =
            paymaster.getHash(userOp, validUntil, validAfter, tokenAddress, tokenPrice, externalPriceMarkup);

        // Sign the hash
        signature = signMessage(signer, paymasterHash);
        require(signature.length == 65, "Invalid Paymaster Signature length");

        // Final paymaster data with the actual signature
        finalPmData = abi.encodePacked(
            address(paymaster),
            paymasterValGasLimit,
            paymasterPostOpGasLimit,
            uint8(mode),
            validUntil,
            validAfter,
            tokenAddress,
            tokenPrice,
            externalPriceMarkup,
            signature
        );
    }

    function excludeLastNBytes(bytes memory data, uint256 n) internal pure returns (bytes memory) {
        require(data.length > n, "Input data is too short");
        bytes memory result = new bytes(data.length - n);
        for (uint256 i = 0; i < data.length - n; i++) {
            result[i] = data[i];
        }
        return result;
    }

    function getPriceMarkups(
        BiconomySponsorshipPaymaster paymaster,
        uint256 initialDappPaymasterBalance,
        uint256 initialFeeCollectorBalance,
        uint32 priceMarkup
    )
        internal
        view
        returns (uint256 expectedPriceMarkup, uint256 actualPriceMarkup)
    {
        uint256 resultingDappPaymasterBalance = paymaster.getBalance(DAPP_ACCOUNT.addr);
        uint256 resultingFeeCollectorPaymasterBalance = paymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr);

        uint256 totalGasFeesCharged = initialDappPaymasterBalance - resultingDappPaymasterBalance;

        if (priceMarkup >= 1e6) {
            //priceMarkup
            expectedPriceMarkup = totalGasFeesCharged - ((totalGasFeesCharged * 1e6) / priceMarkup);
            actualPriceMarkup = resultingFeeCollectorPaymasterBalance - initialFeeCollectorBalance;
        } else {
            revert("PriceMarkup must be more than 1e6");
        }
    }

    function calculateAndAssertAdjustments(
        BiconomySponsorshipPaymaster bicoPaymaster,
        uint256 initialDappPaymasterBalance,
        uint256 initialFeeCollectorBalance,
        uint256 initialBundlerBalance,
        uint256 initialPaymasterEpBalance,
        uint32 priceMarkup
    )
        internal
        view
    {
        (uint256 expectedPriceMarkup, uint256 actualPriceMarkup) =
            getPriceMarkups(bicoPaymaster, initialDappPaymasterBalance, initialFeeCollectorBalance, priceMarkup);
        uint256 totalGasFeePaid = BUNDLER.addr.balance - initialBundlerBalance;
        uint256 gasPaidByDapp = initialDappPaymasterBalance - bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);

        // Assert that what paymaster paid is the same as what the bundler received
        assertEq(totalGasFeePaid, initialPaymasterEpBalance - bicoPaymaster.getDeposit());
        // Assert that adjustment collected (if any) is correct
        assertEq(expectedPriceMarkup, actualPriceMarkup);
        // Gas paid by dapp is higher than paymaster
        // Guarantees that EP always has sufficient deposit to pay back dapps

        // TODO
        // Review: fix this properly. avoid out of stack errors
        assertGt(gasPaidByDapp, BUNDLER.addr.balance - initialBundlerBalance);
        // Ensure that max 1% difference between total gas paid + the adjustment premium and gas paid by dapp (from
        // paymaster)
        assertApproxEqRel(totalGasFeePaid + actualPriceMarkup, gasPaidByDapp, 0.01e18);
    }

    function _toSingletonArray(address addr) internal pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = addr;
        return array;
    }

    function _toSingletonArray(IOracle oracle) internal pure returns (IOracle[] memory) {
        IOracle[] memory array = new IOracle[](1);
        array[0] = oracle;
        return array;
    }
}
