// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IEntryPoint } from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import { PackedUserOperation, UserOperationLib } from "@account-abstraction/contracts/core/UserOperationLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";
import { BasePaymaster } from "../base/BasePaymaster.sol";
import { BiconomyTokenPaymasterErrors } from "../common/BiconomyTokenPaymasterErrors.sol";
import { IBiconomyTokenPaymaster } from "../interfaces/IBiconomyTokenPaymaster.sol";
import { IOracle } from "../interfaces/oracles/IOracle.sol";
import { PaymasterParser } from "../libraries/PaymasterParser.sol";
import { SignatureCheckerLib } from "@solady/src/utils/SignatureCheckerLib.sol";
import { ECDSA as ECDSA_solady } from "@solady/src/utils/ECDSA.sol";
import "@account-abstraction/contracts/core/Helpers.sol";

/**
 * @title BiconomyTokenPaymaster
 * @author ShivaanshK<shivaansh.kapoor@biconomy.io>
 * @author livingrockrises<chirag@biconomy.io>
 * @notice Biconomy's Token Paymaster for Entry Point v0.7
 * @dev  A paymaster that allows user to pay gas fees in ERC20 tokens. The paymaster uses the precharge and refund model
 * to handle gas remittances.
 *
 * Currently, the paymaster supports two modes:
 * 1. EXTERNAL - Relies on a quoted token price from a trusted entity (verifyingSigner).
 * 2. INDEPENDENT - Relies purely on price oracles (Offchain and TWAP) which implement the IOracle interface. This mode
 * doesn't require a signature and is always "available" to use.
 *
 * The paymaster's owner has full discretion over the supported tokens (for independent mode), price adjustments
 * applied, and how
 * to manage the assets received by the paymaster.
 */
contract BiconomyTokenPaymaster is
    BasePaymaster,
    ReentrancyGuardTransient,
    BiconomyTokenPaymasterErrors,
    IBiconomyTokenPaymaster
{
    using UserOperationLib for PackedUserOperation;
    using PaymasterParser for bytes;
    using SignatureCheckerLib for address;

    // State variables
    address public feeCollector;
    address public verifyingSigner;
    uint256 public unaccountedGas;
    uint256 public dynamicAdjustment;
    uint256 public priceExpiryDuration;
    IOracle public nativeOracle; // ETH -> USD price
    mapping(address => TokenInfo) tokenDirectory;

    // PAYMASTER_ID_OFFSET
    uint256 private constant UNACCOUNTED_GAS_LIMIT = 50_000; // Limit for unaccounted gas cost
    uint256 private constant PRICE_DENOMINATOR = 1e6; // Denominator used when calculating cost with dynamic adjustment
    uint256 private constant MAX_DYNAMIC_ADJUSTMENT = 2e6; // 100% premium on price (2e6/PRICE_DENOMINATOR)

    constructor(
        address _owner,
        address _verifyingSigner,
        IEntryPoint _entryPoint,
        uint256 _unaccountedGas,
        uint256 _dynamicAdjustment,
        IOracle _nativeOracle,
        uint256 _priceExpiryDuration,
        address[] memory _tokens, // Array of token addresses
        IOracle[] memory _oracles // Array of corresponding oracle addresses
    )
        BasePaymaster(_owner, _entryPoint)
    {
        if (_isContract(_verifyingSigner)) {
            revert VerifyingSignerCanNotBeContract();
        }
        if (_verifyingSigner == address(0)) {
            revert VerifyingSignerCanNotBeZero();
        }
        if (_unaccountedGas > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
        if (_dynamicAdjustment > MAX_DYNAMIC_ADJUSTMENT || _dynamicAdjustment < PRICE_DENOMINATOR) {
            revert InvalidDynamicAdjustment();
        }
        if (_tokens.length != _oracles.length) {
            revert TokensAndInfoLengthMismatch();
        }
        if (_nativeOracle.decimals() != 8) {
            // ETH -> USD will always have 8 decimals for Chainlink and TWAP
            revert InvalidOracleDecimals();
        }

        // Set state variables
        assembly ("memory-safe") {
            sstore(verifyingSigner.slot, _verifyingSigner)
            sstore(feeCollector.slot, address()) // initialize fee collector to this contract
            sstore(unaccountedGas.slot, _unaccountedGas)
            sstore(dynamicAdjustment.slot, _dynamicAdjustment)
            sstore(priceExpiryDuration.slot, _priceExpiryDuration)
            sstore(nativeOracle.slot, _nativeOracle)
        }

        // Populate the tokenToOracle mapping
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_oracles[i].decimals() != 8) {
                // Token -> USD will always have 8 decimals
                revert InvalidOracleDecimals();
            }
            tokenDirectory[_tokens[i]] = TokenInfo(_oracles[i], 10 ** IERC20Metadata(_tokens[i]).decimals());
        }
    }

    /**
     * Add a deposit in native currency for this paymaster, used for paying for transaction fees.
     * This is ideally done by the entity who is managing the received ERC20 gas tokens.
     */
    function deposit() public payable virtual override nonReentrant {
        entryPoint.depositTo{ value: msg.value }(address(this));
    }

    /**
     * @dev Withdraws the specified amount of gas tokens from the paymaster's balance and transfers them to the
     * specified address.
     * @param withdrawAddress The address to which the gas tokens should be transferred.
     * @param amount The amount of gas tokens to withdraw.
     */
    function withdrawTo(address payable withdrawAddress, uint256 amount) public override onlyOwner nonReentrant {
        if (withdrawAddress == address(0)) revert CanNotWithdrawToZeroAddress();
        entryPoint.withdrawTo(withdrawAddress, amount);
    }

    /**
     * @dev pull tokens out of paymaster in case they were sent to the paymaster at any point.
     * @param token the token deposit to withdraw
     * @param target address to send to
     * @param amount amount to withdraw
     */
    function withdrawERC20(IERC20 token, address target, uint256 amount) external payable onlyOwner nonReentrant {
        _withdrawERC20(token, target, amount);
    }

    /**
     * @dev pull tokens out of paymaster in case they were sent to the paymaster at any point.
     * @param token the token deposit to withdraw
     * @param target address to send to
     */
    function withdrawERC20Full(IERC20 token, address target) external payable onlyOwner nonReentrant {
        uint256 amount = token.balanceOf(address(this));
        _withdrawERC20(token, target, amount);
    }

    /**
     * @dev pull multiple tokens out of paymaster in case they were sent to the paymaster at any point.
     * @param token the tokens deposit to withdraw
     * @param target address to send to
     * @param amount amounts to withdraw
     */
    function withdrawMultipleERC20(
        IERC20[] calldata token,
        address target,
        uint256[] calldata amount
    )
        external
        payable
        onlyOwner
        nonReentrant
    {
        if (token.length != amount.length) {
            revert TokensAndAmountsLengthMismatch();
        }
        unchecked {
            for (uint256 i; i < token.length;) {
                _withdrawERC20(token[i], target, amount[i]);
                ++i;
            }
        }
    }

    /**
     * @dev pull multiple tokens out of paymaster in case they were sent to the paymaster at any point.
     * @param token the tokens deposit to withdraw
     * @param target address to send to
     */
    function withdrawMultipleERC20Full(
        IERC20[] calldata token,
        address target
    )
        external
        payable
        onlyOwner
        nonReentrant
    {
        unchecked {
            for (uint256 i; i < token.length;) {
                uint256 amount = token[i].balanceOf(address(this));
                _withdrawERC20(token[i], target, amount);
                ++i;
            }
        }
    }

    /**
     * @dev Set a new verifying signer address.
     * Can only be called by the owner of the contract.
     * @param _newVerifyingSigner The new address to be set as the verifying signer.
     * @notice If _newVerifyingSigner is set to zero address, it will revert with an error.
     * After setting the new signer address, it will emit an event VerifyingSignerChanged.
     */
    function setSigner(address _newVerifyingSigner) external payable override onlyOwner {
        if (_isContract(_newVerifyingSigner)) revert VerifyingSignerCanNotBeContract();
        if (_newVerifyingSigner == address(0)) {
            revert VerifyingSignerCanNotBeZero();
        }
        address oldSigner = verifyingSigner;
        assembly ("memory-safe") {
            sstore(verifyingSigner.slot, _newVerifyingSigner)
        }
        emit UpdatedVerifyingSigner(oldSigner, _newVerifyingSigner, msg.sender);
    }

    /**
     * @dev Set a new fee collector address.
     * Can only be called by the owner of the contract.
     * @param _newFeeCollector The new address to be set as the fee collector.
     * @notice If _newFeeCollector is set to zero address, it will revert with an error.
     * After setting the new fee collector address, it will emit an event FeeCollectorChanged.
     */
    function setFeeCollector(address _newFeeCollector) external payable override onlyOwner {
        if (_newFeeCollector == address(0)) revert FeeCollectorCanNotBeZero();
        address oldFeeCollector = feeCollector;
        assembly ("memory-safe") {
            sstore(feeCollector.slot, _newFeeCollector)
        }
        emit UpdatedFeeCollector(oldFeeCollector, _newFeeCollector, msg.sender);
    }

    /**
     * @dev Set a new unaccountedEPGasOverhead value.
     * @param _newUnaccountedGas The new value to be set as the unaccounted gas value
     * @notice only to be called by the owner of the contract.
     */
    function setUnaccountedGas(uint256 _newUnaccountedGas) external payable override onlyOwner {
        if (_newUnaccountedGas > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
        uint256 oldUnaccountedGas = unaccountedGas;
        assembly ("memory-safe") {
            sstore(unaccountedGas.slot, _newUnaccountedGas)
        }
        emit UpdatedUnaccountedGas(oldUnaccountedGas, _newUnaccountedGas);
    }

    /**
     * @dev Set a new dynamicAdjustment value.
     * @param _newDynamicAdjustment The new value to be set as the dynamic adjustment
     * @notice only to be called by the owner of the contract.
     */
    function setDynamicAdjustment(uint256 _newDynamicAdjustment) external payable override onlyOwner {
        if (_newDynamicAdjustment > MAX_DYNAMIC_ADJUSTMENT || _newDynamicAdjustment < PRICE_DENOMINATOR) {
            revert InvalidDynamicAdjustment();
        }
        uint256 oldDynamicAdjustment = dynamicAdjustment;
        assembly ("memory-safe") {
            sstore(dynamicAdjustment.slot, _newDynamicAdjustment)
        }
        emit UpdatedFixedDynamicAdjustment(oldDynamicAdjustment, _newDynamicAdjustment);
    }

    /**
     * @dev Set a new dynamicAdjustment value.
     * @param _newPriceExpiryDuration The new value to be set as the unaccounted gas value
     * @notice only to be called by the owner of the contract.
     */
    function setPriceExpiryDuration(uint256 _newPriceExpiryDuration) external payable override onlyOwner {
        uint256 oldPriceExpiryDuration = priceExpiryDuration;
        assembly ("memory-safe") {
            sstore(priceExpiryDuration.slot, _newPriceExpiryDuration)
        }
        emit UpdatedPriceExpiryDuration(oldPriceExpiryDuration, _newPriceExpiryDuration);
    }

    /**
     * @dev Update the native oracle address
     * @param _oracle The new native asset oracle
     * @notice only to be called by the owner of the contract.
     */
    function setNativeOracle(IOracle _oracle) external payable override onlyOwner {
        if (_oracle.decimals() != 8) {
            // Native -> USD will always have 8 decimals
            revert InvalidOracleDecimals();
        }

        IOracle oldNativeOracle = nativeOracle;
        assembly ("memory-safe") {
            sstore(nativeOracle.slot, _oracle)
        }

        emit UpdatedNativeAssetOracle(oldNativeOracle, _oracle);
    }

    /**
     * @dev Set or update a TokenInfo entry in the tokenDirectory mapping.
     * @param _tokenAddress The token address to add or update in directory
     * @param _oracle The oracle to use for the specified token
     * @notice only to be called by the owner of the contract.
     */
    function updateTokenDirectory(address _tokenAddress, IOracle _oracle) external payable override onlyOwner {
        if (_oracle.decimals() != 8) {
            // Token -> USD will always have 8 decimals
            revert InvalidOracleDecimals();
        }

        uint8 decimals = IERC20Metadata(_tokenAddress).decimals();
        tokenDirectory[_tokenAddress] = TokenInfo(_oracle, 10 ** decimals);

        emit UpdatedTokenDirectory(_tokenAddress, _oracle, decimals);
    }

    /**
     * return the hash we're going to sign off-chain (and validate on-chain)
     * this method is called by the off-chain service, to sign the request.
     * it is called on-chain from the validatePaymasterUserOp, to validate the signature.
     * note that this signature covers all fields of the UserOperation, except the "paymasterAndData",
     * which will carry the signature itself.
     */
    function getHash(
        PackedUserOperation calldata userOp,
        uint48 validUntil,
        uint48 validAfter,
        address tokenAddress,
        uint128 tokenPrice,
        uint32 externalDynamicAdjustment
    )
        public
        view
        returns (bytes32)
    {
        //can't use userOp.hash(), since it contains also the paymasterAndData itself.
        address sender = userOp.getSender();
        return keccak256(
            abi.encode(
                sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                uint256(bytes32(userOp.paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET:PAYMASTER_DATA_OFFSET])),
                userOp.preVerificationGas,
                userOp.gasFees,
                block.chainid,
                address(this),
                validUntil,
                validAfter,
                tokenAddress,
                tokenPrice,
                externalDynamicAdjustment
            )
        );
    }

    /**
     * @dev Validate a user operation.
     * This method is abstract in BasePaymaster and must be implemented in derived contracts.
     * @param userOp The user operation.
     * @param userOpHash The hash of the user operation.
     * @param maxCost The maximum cost of the user operation.
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    )
        internal
        override
        returns (bytes memory context, uint256 validationData)
    {
        (PaymasterMode mode, bytes memory modeSpecificData) = userOp.paymasterAndData.parsePaymasterAndData();

        if (uint8(mode) > 1) {
            revert InvalidPaymasterMode();
        }

        if (mode == PaymasterMode.EXTERNAL) {
            // Use the price and other params specified in modeSpecificData by the verifyingSigner
            // Useful for supporting tokens which don't have oracle support

            (
                uint48 validUntil,
                uint48 validAfter,
                address tokenAddress,
                uint128 tokenPrice,
                uint32 externalDynamicAdjustment,
                bytes memory signature
            ) = modeSpecificData.parseExternalModeSpecificData();

            if (signature.length != 64 && signature.length != 65) {
                revert InvalidSignatureLength();
            }

            bool validSig = verifyingSigner.isValidSignatureNow(
                ECDSA_solady.toEthSignedMessageHash(
                    getHash(userOp, validUntil, validAfter, tokenAddress, tokenPrice, externalDynamicAdjustment)
                ),
                signature
            );

            //don't revert on signature failure: return SIG_VALIDATION_FAILED
            if (!validSig) {
                return ("", _packValidationData(true, validUntil, validAfter));
            }

            if (externalDynamicAdjustment > MAX_DYNAMIC_ADJUSTMENT || externalDynamicAdjustment < PRICE_DENOMINATOR) {
                revert InvalidDynamicAdjustment();
            }

            uint256 tokenAmount;
            {
                uint256 maxFeePerGas = UserOperationLib.unpackMaxFeePerGas(userOp);
                tokenAmount = ((maxCost + (unaccountedGas) * maxFeePerGas) * externalDynamicAdjustment * tokenPrice)
                    / (1e18 * PRICE_DENOMINATOR);
            }

            // Transfer full amount to this address. Unused amount will be refunded in postOP
            SafeTransferLib.safeTransferFrom(tokenAddress, userOp.sender, address(this), tokenAmount);

            context = abi.encode(
                userOp.sender, tokenAddress, tokenAmount, tokenPrice, uint256(externalDynamicAdjustment), userOpHash
            );
            validationData = _packValidationData(false, validUntil, validAfter);
        } else if (mode == PaymasterMode.INDEPENDENT) {
            // Use only oracles for the token specified in modeSpecificData
            if (modeSpecificData.length != 20) {
                revert InvalidTokenAddress();
            }

            // Get address for token used to pay
            address tokenAddress = modeSpecificData.parseIndependentModeSpecificData();
            uint192 tokenPrice = getPrice(tokenAddress);
            uint256 tokenAmount;

            {
                // Calculate token amount to precharge
                uint256 maxFeePerGas = UserOperationLib.unpackMaxFeePerGas(userOp);
                tokenAmount = ((maxCost + (unaccountedGas) * maxFeePerGas) * dynamicAdjustment * tokenPrice)
                    / (1e18 * PRICE_DENOMINATOR);
            }

            // Transfer full amount to this address. Unused amount will be refunded in postOP
            SafeTransferLib.safeTransferFrom(tokenAddress, userOp.sender, address(this), tokenAmount);

            context = abi.encode(userOp.sender, tokenAddress, tokenAmount, tokenPrice, dynamicAdjustment, userOpHash);
            validationData = 0; // Validation success and price is valid indefinetly
        }
    }

    /**
     * @dev Post-operation handler.
     * This method is abstract in BasePaymaster and must be implemented in derived contracts.
     * @param context The context value returned by validatePaymasterUserOp.
     * @param actualGasCost Actual gas used so far (excluding this postOp call).
     * @param actualUserOpFeePerGas The gas price this UserOp pays.
     */
    function _postOp(
        PostOpMode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    )
        internal
        override
    {
        // Decode context data
        (
            address userOpSender,
            address tokenAddress,
            uint256 prechargedAmount,
            uint192 tokenPrice,
            uint256 appliedDynamicAdjustment,
            bytes32 userOpHash
        ) = abi.decode(context, (address, address, uint256, uint192, uint256, bytes32));

        // Calculate the actual cost in tokens based on the actual gas cost and the token price
        uint256 actualTokenAmount = (
            (actualGasCost + (unaccountedGas) * actualUserOpFeePerGas) * appliedDynamicAdjustment * tokenPrice
        ) / (1e18 * PRICE_DENOMINATOR);

        // If the user was overcharged, refund the excess tokens
        if (prechargedAmount > actualTokenAmount) {
            uint256 refundAmount = prechargedAmount - actualTokenAmount;
            SafeTransferLib.safeTransfer(tokenAddress, userOpSender, refundAmount);
            emit TokensRefunded(userOpSender, refundAmount, userOpHash);
        }

        // Emit an event for post-operation completion (optional)
        emit PaidGasInTokens(userOpSender, actualGasCost, appliedDynamicAdjustment, userOpHash);
    }

    function _withdrawERC20(IERC20 token, address target, uint256 amount) private {
        if (target == address(0)) revert CanNotWithdrawToZeroAddress();
        SafeTransferLib.safeTransfer(address(token), target, amount);
    }

    /// @notice Fetches the latest token price.
    /// @return price The latest token price fetched from the oracles.
    function getPrice(address tokenAddress) internal view returns (uint192 price) {
        // Fetch token information from directory
        TokenInfo memory tokenInfo = tokenDirectory[tokenAddress];

        if (address(tokenInfo.oracle) == address(0)) {
            // If oracle not set, token isn't supported
            revert TokenNotSupported();
        }

        // Calculate price by using token and native oracle
        uint192 tokenPrice = _fetchPrice(tokenInfo.oracle);
        uint192 nativeAssetPrice = _fetchPrice(nativeOracle);

        // Adjust to token  decimals
        price = nativeAssetPrice * uint192(tokenInfo.decimals) / tokenPrice;
    }

    /// @notice Fetches the latest price from the given oracle.
    /// @dev This function is used to get the latest price from the tokenOracle or nativeAssetOracle.
    /// @param _oracle The oracle contract to fetch the price from.
    /// @return price The latest price fetched from the oracle.
    function _fetchPrice(IOracle _oracle) internal view returns (uint192 price) {
        (, int256 answer,, uint256 updatedAt,) = _oracle.latestRoundData();
        if (answer <= 0) {
            revert OraclePriceNotPositive();
        }
        if (updatedAt < block.timestamp - priceExpiryDuration) {
            revert OraclePriceExpired();
        }
        price = uint192(int192(answer));
    }
}
