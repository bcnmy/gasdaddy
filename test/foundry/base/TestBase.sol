// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/src/Test.sol";
import { Vm } from "forge-std/src/Vm.sol";

import "solady/src/utils/ECDSA.sol";

import { EntryPoint } from "account-abstraction/contracts/core/EntryPoint.sol";
import { IEntryPoint } from "account-abstraction/contracts/interfaces/IEntryPoint.sol";
import { IAccount } from "account-abstraction/contracts/interfaces/IAccount.sol";
import { Exec } from "account-abstraction/contracts/utils/Exec.sol";
import { IPaymaster } from "account-abstraction/contracts/interfaces/IPaymaster.sol";
import { PackedUserOperation } from "account-abstraction/contracts/interfaces/PackedUserOperation.sol";

import { Nexus } from "nexus/contracts/Nexus.sol";
import { NexusAccountFactory } from "nexus/contracts/factory/NexusAccountFactory.sol";
import { BiconomyMetaFactory } from "nexus/contracts/factory/BiconomyMetaFactory.sol";
import { MockValidator } from "nexus/contracts/mocks/MockValidator.sol";
import { BootstrapLib } from "nexus/contracts/lib/BootstrapLib.sol";
import { Bootstrap, BootstrapConfig } from "nexus/contracts/utils/Bootstrap.sol";
import { CheatCodes } from "nexus/test/foundry/utils/CheatCodes.sol";
import { BaseEventsAndErrors } from "./BaseEventsAndErrors.sol";

import { BiconomySponsorshipPaymaster } from "../../../contracts/sponsorship/BiconomySponsorshipPaymaster.sol";

abstract contract TestBase is CheatCodes, BaseEventsAndErrors {
    // -----------------------------------------
    // State Variables
    // -----------------------------------------

    Vm.Wallet internal DEPLOYER;
    Vm.Wallet internal ALICE;
    Vm.Wallet internal BOB;
    Vm.Wallet internal CHARLIE;
    Vm.Wallet internal DAN;
    Vm.Wallet internal EMMA;
    Vm.Wallet internal BUNDLER;
    Vm.Wallet internal PAYMASTER_OWNER;
    Vm.Wallet internal PAYMASTER_SIGNER;
    Vm.Wallet internal PAYMASTER_FEE_COLLECTOR;
    Vm.Wallet internal DAPP_ACCOUNT;
    Vm.Wallet internal FACTORY_OWNER;

    address internal ALICE_ADDRESS;
    address internal BOB_ADDRESS;
    address internal CHARLIE_ADDRESS;
    address internal DAN_ADDRESS;
    address internal EMMA_ADDRESS;

    Nexus internal ALICE_ACCOUNT;
    Nexus internal BOB_ACCOUNT;
    Nexus internal CHARLIE_ACCOUNT;
    Nexus internal DAN_ACCOUNT;
    Nexus internal EMMA_ACCOUNT;

    address constant ENTRYPOINT_ADDRESS = address(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    IEntryPoint internal ENTRYPOINT;

    NexusAccountFactory internal FACTORY;
    BiconomyMetaFactory internal META_FACTORY;
    MockValidator internal VALIDATOR_MODULE;
    Nexus internal ACCOUNT_IMPLEMENTATION;
    Bootstrap internal BOOTSTRAPPER;

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
    function setupTestEnvironment() internal virtual {
        /// Initializes the testing environment
        setupPredefinedWallets();
        deployTestContracts();
        deployNexusForPredefinedWallets();
    }

    function createAndFundWallet(string memory name, uint256 amount) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory wallet = newWallet(name);
        vm.deal(wallet.addr, amount);
        return wallet;
    }

    function setupPredefinedWallets() internal {
        DEPLOYER = createAndFundWallet("DEPLOYER", 1000 ether);
        BUNDLER = createAndFundWallet("BUNDLER", 1000 ether);

        ALICE = createAndFundWallet("ALICE", 1000 ether);
        BOB = createAndFundWallet("BOB", 1000 ether);
        CHARLIE = createAndFundWallet("CHARLIE", 1000 ether);
        DAN = createAndFundWallet("DAN", 1000 ether);
        EMMA = createAndFundWallet("EMMA", 1000 ether);

        ALICE_ADDRESS = ALICE.addr;
        BOB_ADDRESS = BOB.addr;
        CHARLIE_ADDRESS = CHARLIE.addr;
        DAN_ADDRESS = DAN.addr;
        EMMA_ADDRESS = EMMA.addr;

        PAYMASTER_OWNER = createAndFundWallet("PAYMASTER_OWNER", 1000 ether);
        PAYMASTER_SIGNER = createAndFundWallet("PAYMASTER_SIGNER", 1000 ether);
        PAYMASTER_FEE_COLLECTOR = createAndFundWallet("PAYMASTER_FEE_COLLECTOR", 1000 ether);
        DAPP_ACCOUNT = createAndFundWallet("DAPP_ACCOUNT", 1000 ether);
        FACTORY_OWNER = createAndFundWallet("FACTORY_OWNER", 1000 ether);
    }

    function deployTestContracts() internal {
        ENTRYPOINT = new EntryPoint();
        vm.etch(ENTRYPOINT_ADDRESS, address(ENTRYPOINT).code);
        ENTRYPOINT = IEntryPoint(ENTRYPOINT_ADDRESS);
        ACCOUNT_IMPLEMENTATION = new Nexus(address(ENTRYPOINT));
        FACTORY = new NexusAccountFactory(address(ACCOUNT_IMPLEMENTATION), address(FACTORY_OWNER.addr));
        META_FACTORY = new BiconomyMetaFactory(address(FACTORY_OWNER.addr));
        vm.prank(FACTORY_OWNER.addr);
        META_FACTORY.addFactoryToWhitelist(address(FACTORY));
        VALIDATOR_MODULE = new MockValidator();
        BOOTSTRAPPER = new Bootstrap();
    }

    // -----------------------------------------
    // Account Deployment Functions
    // -----------------------------------------
    /// @notice Deploys an account with a specified wallet, deposit amount, and optional custom validator
    /// @param wallet The wallet to deploy the account for
    /// @param deposit The deposit amount
    /// @param validator The custom validator address, if not provided uses default
    /// @return The deployed Nexus account
    function deployNexus(Vm.Wallet memory wallet, uint256 deposit, address validator) internal returns (Nexus) {
        address payable accountAddress = calculateAccountAddress(wallet.addr, validator);
        bytes memory initCode = buildInitCode(wallet.addr, validator);

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = buildUserOpWithInitAndCalldata(wallet, initCode, "", validator);

        ENTRYPOINT.depositTo{ value: deposit }(address(accountAddress));
        ENTRYPOINT.handleOps(userOps, payable(wallet.addr));
        assertTrue(MockValidator(validator).isOwner(accountAddress, wallet.addr));
        return Nexus(accountAddress);
    }

    /// @notice Deploys Nexus accounts for predefined wallets
    function deployNexusForPredefinedWallets() internal {
        BOB_ACCOUNT = deployNexus(BOB, 100 ether, address(VALIDATOR_MODULE));
        vm.label(address(BOB_ACCOUNT), "BOB_ACCOUNT");
        ALICE_ACCOUNT = deployNexus(ALICE, 100 ether, address(VALIDATOR_MODULE));
        vm.label(address(ALICE_ACCOUNT), "ALICE_ACCOUNT");
        CHARLIE_ACCOUNT = deployNexus(CHARLIE, 100 ether, address(VALIDATOR_MODULE));
        vm.label(address(CHARLIE_ACCOUNT), "CHARLIE_ACCOUNT");
        DAN_ACCOUNT = deployNexus(DAN, 100 ether, address(VALIDATOR_MODULE));
        vm.label(address(DAN_ACCOUNT), "DAN_ACCOUNT");
        EMMA_ACCOUNT = deployNexus(EMMA, 100 ether, address(VALIDATOR_MODULE));
        vm.label(address(EMMA_ACCOUNT), "EMMA_ACCOUNT");
    }
    // -----------------------------------------
    // Utility Functions
    // -----------------------------------------

    /// @notice Calculates the address of a new account
    /// @param owner The address of the owner
    /// @param validator The address of the validator
    /// @return account The calculated account address
    function calculateAccountAddress(
        address owner,
        address validator
    )
        internal
        view
        returns (address payable account)
    {
        bytes memory moduleInstallData = abi.encodePacked(owner);

        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(validator, moduleInstallData);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        bytes memory saDeploymentIndex = "0";

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook);
        bytes32 salt = keccak256(saDeploymentIndex);

        account = FACTORY.computeAccountAddress(_initData, salt);
        return account;
    }

    /// @notice Prepares the init code for account creation with a validator
    /// @param ownerAddress The address of the owner
    /// @param validator The address of the validator
    /// @return initCode The prepared init code
    function buildInitCode(address ownerAddress, address validator) internal view returns (bytes memory initCode) {
        bytes memory moduleInitData = abi.encodePacked(ownerAddress);

        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(validator, moduleInitData);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");

        bytes memory saDeploymentIndex = "0";

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook);

        bytes32 salt = keccak256(saDeploymentIndex);

        bytes memory factoryData = abi.encodeWithSelector(FACTORY.createAccount.selector, _initData, salt);

        // Prepend the factory address to the encoded function call to form the initCode
        initCode = abi.encodePacked(
            address(META_FACTORY),
            abi.encodeWithSelector(META_FACTORY.deployWithFactory.selector, address(FACTORY), factoryData)
        );
    }

    /// @notice Prepares a user operation with init code and call data
    /// @param wallet The wallet for which the user operation is prepared
    /// @param initCode The init code
    /// @param callData The call data
    /// @param validator The validator address
    /// @return userOp The prepared user operation
    function buildUserOpWithInitAndCalldata(
        Vm.Wallet memory wallet,
        bytes memory initCode,
        bytes memory callData,
        address validator
    )
        internal
        view
        returns (PackedUserOperation memory userOp)
    {
        userOp = buildUserOpWithCalldata(wallet, callData, validator);
        userOp.initCode = initCode;

        bytes memory signature = signUserOp(wallet, userOp);
        userOp.signature = signature;
    }

    /// @notice Prepares a user operation with call data and a validator
    /// @param wallet The wallet for which the user operation is prepared
    /// @param callData The call data
    /// @param validator The validator address
    /// @return userOp The prepared user operation
    function buildUserOpWithCalldata(
        Vm.Wallet memory wallet,
        bytes memory callData,
        address validator
    )
        internal
        view
        returns (PackedUserOperation memory userOp)
    {
        address payable account = calculateAccountAddress(wallet.addr, validator);
        uint256 nonce = getNonce(account, validator);
        userOp = buildPackedUserOp(account, nonce);
        userOp.callData = callData;

        bytes memory signature = signUserOp(wallet, userOp);
        userOp.signature = signature;
    }

    /// @notice Retrieves the nonce for a given account and validator
    /// @param account The account address
    /// @param validator The validator address
    /// @return nonce The retrieved nonce
    function getNonce(address account, address validator) internal view returns (uint256 nonce) {
        uint192 key = uint192(bytes24(bytes20(address(validator))));
        nonce = ENTRYPOINT.getNonce(address(account), key);
    }

    /// @notice Signs a user operation
    /// @param wallet The wallet to sign the operation
    /// @param userOp The user operation to sign
    /// @return The signed user operation
    function signUserOp(
        Vm.Wallet memory wallet,
        PackedUserOperation memory userOp
    )
        internal
        view
        returns (bytes memory)
    {
        bytes32 opHash = ENTRYPOINT.getUserOpHash(userOp);
        return signMessage(wallet, opHash);
    }

    // -----------------------------------------
    // Utility Functions
    // -----------------------------------------

    /// @notice Modifies the address of a deployed contract in a test environment
    /// @param originalAddress The original address of the contract
    /// @param newAddress The new address to replace the original
    function changeContractAddress(address originalAddress, address newAddress) internal {
        vm.etch(newAddress, originalAddress.code);
    }

    /// @notice Builds a user operation struct for account abstraction tests
    /// @param sender The sender address
    /// @param nonce The nonce
    /// @return userOp The built user operation
    function buildPackedUserOp(address sender, uint256 nonce) internal pure returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(abi.encodePacked(uint128(3e6), uint128(3e6))), // verification and call gas limit
            preVerificationGas: 3e5, // Adjusted preVerificationGas
            gasFees: bytes32(abi.encodePacked(uint128(3e6), uint128(3e6))), // maxFeePerGas and maxPriorityFeePerGas
            paymasterAndData: "",
            signature: ""
        });
    }

    /// @notice Signs a message and packs r, s, v into bytes
    /// @param wallet The wallet to sign the message
    /// @param messageHash The hash of the message to sign
    /// @return signature The packed signature
    function signMessage(Vm.Wallet memory wallet, bytes32 messageHash) internal pure returns (bytes memory signature) {
        bytes32 userOpHash = ECDSA.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wallet.privateKey, userOpHash);
        signature = abi.encodePacked(r, s, v);
    }

    /// @notice Pre-funds a smart account and asserts success
    /// @param sa The smart account address
    /// @param prefundAmount The amount to pre-fund
    function prefundSmartAccountAndAssertSuccess(address sa, uint256 prefundAmount) internal {
        (bool res,) = sa.call{ value: prefundAmount }(""); // Pre-funding the account contract
        assertTrue(res, "Pre-funding account should succeed");
    }

    function estimateUserOpGasCosts(PackedUserOperation memory userOp)
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
        uint32 dynamicAdjustment
    )
        internal
        returns (PackedUserOperation memory userOp, bytes32 userOpHash)
    {
        // Create userOp with no gas estimates
        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);

        userOp = buildUserOpWithCalldata(sender, "", address(VALIDATOR_MODULE));

        (userOp.paymasterAndData,) = generateAndSignPaymasterData(
            userOp, PAYMASTER_SIGNER, paymaster, 3e6, 3e6, DAPP_ACCOUNT.addr, validUntil, validAfter, dynamicAdjustment
        );
        userOp.signature = signUserOp(sender, userOp);

        (,, uint256 verificationGasLimit, uint256 callGasLimit) = estimateUserOpGasCosts(userOp);
        // Estimate paymaster gas limits
        (, uint256 postopGasUsed, uint256 validationGasLimit, uint256 postopGasLimit) =
            estimatePaymasterGasCosts(paymaster, userOp, 5e4);

        vm.startPrank(paymaster.owner());
        // Set unaccounted gas to be gas used in postop + 1000 for EP overhead and penalty
        paymaster.setUnaccountedGas(uint48(postopGasUsed + 1000));
        vm.stopPrank();

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
            dynamicAdjustment
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
        uint32 dynamicAdjustment
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
            dynamicAdjustment,
            new bytes(65) // Zero signature
        );

        // Update user operation with initial paymaster data
        userOp.paymasterAndData = initialPmData;

        // Generate hash to be signed
        bytes32 paymasterHash = paymaster.getHash(userOp, paymasterId, validUntil, validAfter, dynamicAdjustment);

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
            dynamicAdjustment,
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

    function getDynamicAdjustments(
        BiconomySponsorshipPaymaster paymaster,
        uint256 initialDappPaymasterBalance,
        uint256 initialFeeCollectorBalance,
        uint32 dynamicAdjustment
    )
        internal
        view
        returns (uint256 expectedDynamicAdjustment, uint256 actualDynamicAdjustment)
    {
        uint256 resultingDappPaymasterBalance = paymaster.getBalance(DAPP_ACCOUNT.addr);
        uint256 resultingFeeCollectorPaymasterBalance = paymaster.getBalance(PAYMASTER_FEE_COLLECTOR.addr);

        uint256 totalGasFeesCharged = initialDappPaymasterBalance - resultingDappPaymasterBalance;

        if (dynamicAdjustment >= 1e6) {
            //dynamicAdjustment
            expectedDynamicAdjustment = totalGasFeesCharged - ((totalGasFeesCharged * 1e6) / dynamicAdjustment);
            actualDynamicAdjustment = resultingFeeCollectorPaymasterBalance - initialFeeCollectorBalance;
        } else {
            revert("DynamicAdjustment must be more than 1e6");
        }
    }

    function calculateAndAssertAdjustments(
        BiconomySponsorshipPaymaster bicoPaymaster,
        uint256 initialDappPaymasterBalance,
        uint256 initialFeeCollectorBalance,
        uint256 initialBundlerBalance,
        uint256 initialPaymasterEpBalance,
        uint32 dynamicAdjustment
    )
        internal
    {
        (uint256 expectedDynamicAdjustment, uint256 actualDynamicAdjustment) = getDynamicAdjustments(
            bicoPaymaster, initialDappPaymasterBalance, initialFeeCollectorBalance, dynamicAdjustment
        );
        uint256 totalGasFeePaid = BUNDLER.addr.balance - initialBundlerBalance;
        uint256 gasPaidByDapp = initialDappPaymasterBalance - bicoPaymaster.getBalance(DAPP_ACCOUNT.addr);

        // Assert that what paymaster paid is the same as what the bundler received
        assertEq(totalGasFeePaid, initialPaymasterEpBalance - bicoPaymaster.getDeposit());
        // Assert that adjustment collected (if any) is correct
        assertEq(expectedDynamicAdjustment, actualDynamicAdjustment);
        // Gas paid by dapp is higher than paymaster
        // Guarantees that EP always has sufficient deposit to pay back dapps
        assertGt(gasPaidByDapp, BUNDLER.addr.balance - initialBundlerBalance);
        // Ensure that max 1% difference between total gas paid + the adjustment premium and gas paid by dapp (from
        // paymaster)
        assertApproxEqRel(totalGasFeePaid + actualDynamicAdjustment, gasPaidByDapp, 0.01e18);
    }
}
