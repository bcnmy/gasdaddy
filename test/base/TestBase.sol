// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";

import "solady/utils/ECDSA.sol";
import "./TestHelper.sol";
import "account-abstraction/core/UserOperationLib.sol";

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

    using UserOperationLib for PackedUserOperation;

    address constant ENTRYPOINT_ADDRESS = address(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    address constant WRAPPED_NATIVE_ADDRESS = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant SWAP_ROUTER_ADDRESS = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    Vm.Wallet internal PAYMASTER_OWNER;
    Vm.Wallet internal PAYMASTER_SIGNER;
    Vm.Wallet internal PAYMASTER_FEE_COLLECTOR;
    Vm.Wallet internal DAPP_ACCOUNT;

    uint256 internal constant _PAYMASTER_POSTOP_GAS_OFFSET = UserOperationLib.PAYMASTER_POSTOP_GAS_OFFSET;
    uint256 internal constant _PAYMASTER_DATA_OFFSET = UserOperationLib.PAYMASTER_DATA_OFFSET;

    struct PaymasterData {
        uint128 validationGasLimit;
        uint128 postOpGasLimit;
        address paymasterId;
        uint48 validUntil;
        uint48 validAfter;
        uint32 priceMarkup;
    }

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
        verificationGasUsed = verificationGasUsed - gasleft(); //+ 21000;

        callGasUsed = gasleft();
        bool success = Exec.call(userOp.sender, 0, userOp.callData, 3e6);
        callGasUsed = callGasUsed - gasleft(); //+ 21000;
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
        validationGasUsed = validationGasUsed - gasleft(); //+ 21000;

        postopGasUsed = gasleft();
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, 1e12, 3e6);
        postopGasUsed = (postopGasUsed - gasleft()); //+ 21000;

        validationGasLimit = (validationGasUsed * GAS_BUFFER_RATIO) / 100;
        postopGasLimit = (postopGasUsed * GAS_BUFFER_RATIO) / 100;
    }

    // Note: we can use externally provided gas limits to override.
    // Note: we can pass callData and callGasLimit as args to test with more tx types
    // Note: we can pass Nexus instance instead of sender EOA and comuting counterfactual within buildUserOpWithCalldata

    function createUserOp(
        Vm.Wallet memory sender,
        BiconomySponsorshipPaymaster paymaster,
        uint32 priceMarkup,
        uint128 postOpGasLimitOverride
    )
        internal
        returns (PackedUserOperation memory userOp, bytes32 userOpHash)
    {
        // Create userOp with no gas estimates
        userOp = buildUserOpWithCalldata(sender, "", address(VALIDATOR_MODULE));

        PaymasterData memory pmData = PaymasterData({
            validationGasLimit: 100_000,
            postOpGasLimit: uint128(postOpGasLimitOverride),
            paymasterId: DAPP_ACCOUNT.addr,
            validUntil: uint48(block.timestamp + 1 days),
            validAfter: uint48(block.timestamp),
            priceMarkup: priceMarkup
        });
        (userOp.paymasterAndData,) = generateAndSignPaymasterData(userOp, PAYMASTER_SIGNER, paymaster, pmData);
        userOp.signature = signUserOp(sender, userOp);

        // Estimate account gas limits
        // (,, uint256 verificationGasLimit, uint256 callGasLimit) = estimateUserOpGasCosts(userOp);
        // // Estimate paymaster gas limits
        // (, uint256 postopGasUsed, uint256 validationGasLimit, uint256 postopGasLimit) =
        //     estimatePaymasterGasCosts(paymaster, userOp, 5e4);

        // vm.startPrank(paymaster.owner());
        // paymaster.setUnaccountedGas(postopGasUsed + 500);
        // vm.stopPrank();

        // Ammend the userop to have updated / overridden gas limits
        userOp.accountGasLimits = bytes32(abi.encodePacked(uint128(100_000), uint128(0)));
        PaymasterData memory pmDataNew = PaymasterData(
            uint128(100_000),
            uint128(postOpGasLimitOverride),
            DAPP_ACCOUNT.addr,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp),
            priceMarkup
        );

        (userOp.paymasterAndData,) = generateAndSignPaymasterData(userOp, PAYMASTER_SIGNER, paymaster, pmDataNew);
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
        PaymasterData memory pmData
    )
        internal
        view
        returns (bytes memory finalPmData, bytes memory signature)
    {
        // Initial paymaster data with zero signature
        userOp.paymasterAndData = abi.encodePacked(
            address(paymaster),
            pmData.validationGasLimit,
            pmData.postOpGasLimit,
            pmData.paymasterId,
            pmData.validUntil,
            pmData.validAfter,
            pmData.priceMarkup,
            new bytes(65) // Zero signature
        );
        
        {
        // Generate hash to be signed
        bytes32 paymasterHash =
            paymaster.getHash(userOp, pmData.paymasterId, pmData.validUntil, pmData.validAfter, pmData.priceMarkup);

        // Sign the hash
        signature = signMessage(signer, paymasterHash);
        }

        // Final paymaster data with the actual signature
        finalPmData = abi.encodePacked(
            address(paymaster),
            pmData.validationGasLimit,
            pmData.postOpGasLimit,
            pmData.paymasterId,
            pmData.validUntil,
            pmData.validAfter,
            pmData.priceMarkup,
            signature
        );
    }

    // Note: Token paymaster could also get into stack deep issues.
    // TODO: Refactor to reduce stack depth
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
        uint32 priceMarkup,
        uint256 maxPenalty
    )
        internal
        view
        returns (uint256 expectedPriceMarkup, uint256 actualPriceMarkup)
    {
        uint256 resultingDappPaymasterBalance = paymaster.getBalance(DAPP_ACCOUNT.addr);
        uint256 resultingFeeCollectorPaymasterBalance = paymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr);

        uint256 totalGasFeesCharged = initialDappPaymasterBalance - resultingDappPaymasterBalance;
        uint256 accountableGasFeesCharged = totalGasFeesCharged - maxPenalty;

        expectedPriceMarkup = accountableGasFeesCharged - ((accountableGasFeesCharged * 1e6) / priceMarkup);
        actualPriceMarkup = resultingFeeCollectorPaymasterBalance - initialFeeCollectorBalance;
    }

    function getMaxPenalty(PackedUserOperation calldata userOp) public view returns (uint256) {
        return (
            uint128(uint256(userOp.accountGasLimits)) + 
            uint128(bytes16(userOp.paymasterAndData[_PAYMASTER_POSTOP_GAS_OFFSET : _PAYMASTER_DATA_OFFSET]))
        ) * 10 * userOp.unpackMaxFeePerGas() / 100;
    }

    // Note: can pack values into one struct
    function calculateAndAssertAdjustments(
        BiconomySponsorshipPaymaster bicoPaymaster,
        uint256 initialDappPaymasterBalance,
        uint256 initialFeeCollectorBalance,
        uint256 initialBundlerBalance,
        uint256 initialPaymasterEpBalance,
        uint32 priceMarkup,
        uint256 maxPenalty
    )
        internal
        view
    {
        (uint256 expectedPriceMarkup, uint256 actualPriceMarkup) =
            getPriceMarkups(bicoPaymaster, initialDappPaymasterBalance, initialFeeCollectorBalance, priceMarkup, maxPenalty);
        uint256 totalGasFeePaid = BUNDLER.addr.balance - initialBundlerBalance;
        uint256 gasPaidByDapp = initialDappPaymasterBalance - bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);

        // Assert that what paymaster paid is the same as what the bundler received
        assertEq(totalGasFeePaid, initialPaymasterEpBalance - bicoPaymaster.getDeposit());
        // Assert that adjustment collected (if any) is correct
        assertEq(expectedPriceMarkup, actualPriceMarkup);
        // Gas paid by dapp is higher than paymaster
        // Guarantees that EP always has sufficient deposit to pay back dapps
        assertGt(gasPaidByDapp, BUNDLER.addr.balance - initialBundlerBalance);
        // Ensure that max 2% difference between total gas paid + the adjustment premium and gas paid by dapp (from
        // paymaster)
        assertApproxEqRel(totalGasFeePaid + actualPriceMarkup + maxPenalty, gasPaidByDapp, 0.02e18);
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
