// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IEntryPoint } from "account-abstraction/interfaces/IEntryPoint.sol";
import { PackedUserOperation, UserOperationLib } from "account-abstraction/core/UserOperationLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { BasePaymaster } from "../base/BasePaymaster.sol";
import { BiconomyTokenPaymasterErrors } from "../common/BiconomyTokenPaymasterErrors.sol";
import { IBiconomyTokenPaymaster } from "../interfaces/IBiconomyTokenPaymaster.sol";
import { IOracle } from "../interfaces/oracles/IOracle.sol";
import { TokenPaymasterParserLib } from "../libraries/TokenPaymasterParserLib.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";
import { ECDSA as ECDSA_solady } from "solady/utils/ECDSA.sol";
import { Uniswapper, IV3SwapRouter } from "./swaps/Uniswapper.sol";
import "account-abstraction/core/Helpers.sol";

/**
 * @title BiconomyTokenPaymaster
 * @author ShivaanshK<shivaansh.kapoor@biconomy.io>
 * @author livingrockrises<chirag@biconomy.io>
 * @notice Biconomy's Token Paymaster for Entry Point v0.7
 * @dev  A paymaster that allows users to pay gas fees in ERC20 tokens. The paymaster uses the precharge and refund
 * model
 * to handle gas remittances.
 *
 * Currently, the paymaster supports two modes:
 * 1. EXTERNAL - Relies on a quoted token price from a trusted entity (verifyingSigner).
 * 2. INDEPENDENT - Relies purely on price oracles (Chainlink and TWAP) which implement the IOracle interface. This mode
 * doesn't require a signature and is "always available" to use.
 *
 * The paymaster's owner has full discretion over the supported tokens (for independent mode), price adjustments
 * applied, and how
 * to manage the assets received by the paymaster.
 */
contract BiconomyTokenPaymaster is
    IBiconomyTokenPaymaster,
    BasePaymaster,
    ReentrancyGuardTransient,
    BiconomyTokenPaymasterErrors,
    Uniswapper
{
    using UserOperationLib for PackedUserOperation;
    using TokenPaymasterParserLib for bytes;
    using SignatureCheckerLib for address;

    // State variables
    address public verifyingSigner; // entity used to provide external token price and markup
    uint256 public unaccountedGas;
    IOracle public nativeAssetToUsdOracle; // ETH -> USD price oracle
    mapping(address => TokenInfo) public independentTokenDirectory; // mapping of token address => info for tokens
    uint256 private constant _UNACCOUNTED_GAS_LIMIT = 200_000; // Limit for unaccounted gas cost
    uint32 private constant _PRICE_DENOMINATOR = 1e6; // Denominator used when calculating cost with price markup
    uint32 private constant _MAX_PRICE_MARKUP = 2e6; // 100% premium on price (2e6/PRICE_DENOMINATOR)
    uint256 private immutable _NATIVE_TOKEN_DECIMALS;  // gas savings
    uint256 private immutable _NATIVE_ASSET_PRICE_EXPIRY_DURATION; // gas savings

    /**
     * @dev markup and expiry duration are provided for each token.
     * Price expiry duration should be set to the heartbeat value of the token. 
     * Additionally, priceMarkup must be higher than Chainlink’s deviation threshold value.
     * More: https://docs.chain.link/architecture-overview/architecture-decentralized-model 
     */

    constructor(
        address owner,
        address verifyingSignerArg,
        IEntryPoint entryPoint,
        uint256 unaccountedGasArg,
        uint256 nativeAssetDecimalsArg,
        IOracle nativeAssetToUsdOracleArg,
        uint256 nativeAssetPriceExpiryDurationArg,
        IV3SwapRouter uniswapRouterArg,
        address wrappedNativeArg,
        address[] memory independentTokensArg, // Array of tokens supported in independent mode
        TokenInfo[] memory tokenInfosArg, // Array of corresponding tokenInfo objects
        address[] memory swappableTokens, // Array of tokens that you want swappable by the uniswapper
        uint24[] memory swappableTokenPoolFeeTiers // Array of uniswap pool fee tiers for each swappable token
    )
        BasePaymaster(owner, entryPoint)
        Uniswapper(uniswapRouterArg, wrappedNativeArg, swappableTokens, swappableTokenPoolFeeTiers)
    {
        _NATIVE_TOKEN_DECIMALS = nativeAssetDecimalsArg;
        _NATIVE_ASSET_PRICE_EXPIRY_DURATION = nativeAssetPriceExpiryDurationArg;

        if (_isContract(verifyingSignerArg)) {
            revert VerifyingSignerCanNotBeContract();
        }
        if (verifyingSignerArg == address(0)) {
            revert VerifyingSignerCanNotBeZero();
        }
        if (unaccountedGasArg > _UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }

        if (independentTokensArg.length != tokenInfosArg.length) {
            revert TokensAndInfoLengthMismatch();
        }
        if (nativeAssetToUsdOracleArg.decimals() != 8) {
            // ETH -> USD will always have 8 decimals for Chainlink and TWAP
            revert InvalidOracleDecimals();
        }

        // Set state variables
        assembly ("memory-safe") {
            sstore(verifyingSigner.slot, verifyingSignerArg)
            sstore(unaccountedGas.slot, unaccountedGasArg)
            sstore(nativeAssetToUsdOracle.slot, nativeAssetToUsdOracleArg)
        }

        for (uint256 i = 0; i < independentTokensArg.length; i++) {
            _validateTokenInfo(tokenInfosArg[i]);
            independentTokenDirectory[independentTokensArg[i]] = tokenInfosArg[i]; 
        }
    }

    receive() external payable {
        // no need to emit an event here
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
     * @dev Withdraw ETH from the paymaster
     * @param recipient The address to send the ETH to
     * @param amount The amount of ETH to withdraw
     */
    function withdrawEth(address payable recipient, uint256 amount) external payable onlyOwner nonReentrant {
        (bool success,) = recipient.call{ value: amount }("");
        if (!success) {
            revert WithdrawalFailed();
        }
        emit EthWithdrawn(recipient, amount);
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
     * @param newVerifyingSigner The new address to be set as the verifying signer.
     * @notice If newVerifyingSigner is set to zero address, it will revert with an error.
     * After setting the new signer address, it will emit an event UpdatedVerifyingSigner.
     */
    function setSigner(address newVerifyingSigner) external payable onlyOwner {
        if (_isContract(newVerifyingSigner)) revert VerifyingSignerCanNotBeContract();
        if (newVerifyingSigner == address(0)) {
            revert VerifyingSignerCanNotBeZero();
        }
        address oldSigner = verifyingSigner;
        assembly ("memory-safe") {
            sstore(verifyingSigner.slot, newVerifyingSigner)
        }
        emit UpdatedVerifyingSigner(oldSigner, newVerifyingSigner, msg.sender);
    }

    /**
     * @dev Set a new unaccountedEPGasOverhead value.
     * @param newUnaccountedGas The new value to be set as the unaccounted gas value
     * @notice only to be called by the owner of the contract.
     */
    function setUnaccountedGas(uint256 newUnaccountedGas) external payable onlyOwner {
        if (newUnaccountedGas > _UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
        uint256 oldUnaccountedGas = unaccountedGas;
        assembly ("memory-safe") {
            sstore(unaccountedGas.slot, newUnaccountedGas)
        }
        emit UpdatedUnaccountedGas(oldUnaccountedGas, newUnaccountedGas);
    }

    /**
     * @dev Set a new priceMarkup value.
     * @param newIndependentPriceMarkup The new value to be set as the price markup
     * @notice only to be called by the owner of the contract.
     */
    function setPriceMarkupForToken(address tokenAddress, uint32 newIndependentPriceMarkup) external payable onlyOwner {
        if (newIndependentPriceMarkup > _MAX_PRICE_MARKUP || newIndependentPriceMarkup < _PRICE_DENOMINATOR) {
            // Not between 0% and 100% markup
            revert InvalidPriceMarkup();
        }
        uint32 oldIndependentPriceMarkup = independentTokenDirectory[tokenAddress].priceMarkup;
        independentTokenDirectory[tokenAddress].priceMarkup = newIndependentPriceMarkup;
        emit UpdatedFixedPriceMarkup(oldIndependentPriceMarkup, newIndependentPriceMarkup);
    }

    /**
     * @dev Set a new price expiry duration.
     * @param newPriceExpiryDuration The new value to be set as the price expiry duration
     * @notice only to be called by the owner of the contract.
     */
    function setPriceExpiryDurationForToken(address tokenAddress, uint256 newPriceExpiryDuration) external payable onlyOwner {
        if(block.timestamp < newPriceExpiryDuration) revert InvalidPriceExpiryDuration();
        uint256 oldPriceExpiryDuration = independentTokenDirectory[tokenAddress].priceExpiryDuration;
        independentTokenDirectory[tokenAddress].priceExpiryDuration = newPriceExpiryDuration;
        emit UpdatedPriceExpiryDuration(oldPriceExpiryDuration, newPriceExpiryDuration);
    }

    /**
     * @dev Update the native oracle address
     * @param oracle The new native asset oracle
     * @notice only to be called by the owner of the contract.
     */
    function setNativeAssetToUsdOracle(IOracle oracle) external payable onlyOwner {
        if (oracle.decimals() != 8) {
            // Native -> USD will always have 8 decimals
            revert InvalidOracleDecimals();
        }

        IOracle oldNativeAssetToUsdOracle = nativeAssetToUsdOracle;
        assembly ("memory-safe") {
            sstore(nativeAssetToUsdOracle.slot, oracle)
        }

        emit UpdatedNativeAssetOracle(oldNativeAssetToUsdOracle, oracle);
    }

    /**
     * @dev Set or update a TokenInfo entry in the independentTokenDirectory mapping.
     * @param tokenAddress The token address to add or update in directory
     * @param tokenInfo The TokenInfo struct to add or update
     * @notice only to be called by the owner of the contract.
     */
    function addToTokenDirectory(address tokenAddress, TokenInfo memory tokenInfo) external payable onlyOwner {
        _validateTokenInfo(tokenInfo);

        independentTokenDirectory[tokenAddress] = tokenInfo;

        emit AddedToTokenDirectory(tokenAddress, tokenInfo.oracle, IERC20Metadata(tokenAddress).decimals());
    }

    /**
     * @dev Remove a token from the independentTokenDirectory mapping.
     * @param tokenAddress The token address to remove from directory
     * @notice only to be called by the owner of the contract.
     */
    function removeFromTokenDirectory(address tokenAddress) external payable onlyOwner {
        delete independentTokenDirectory[tokenAddress];
        emit RemovedFromTokenDirectory(tokenAddress);
    }

    /**
     * @dev Update or add a swappable token to the Uniswapper
     * @param tokenAddresses The token address to add/update to/for uniswapper
     * @param poolFeeTiers The pool fee tiers for the corresponding token address to use
     * @notice only to be called by the owner of the contract.
     */
    function updateSwappableTokens(
        address[] memory tokenAddresses,
        uint24[] memory poolFeeTiers
    )
        external
        payable
        onlyOwner
    {
        if (tokenAddresses.length != poolFeeTiers.length) {
            revert TokensAndPoolsLengthMismatch();
        }

        for (uint256 i = 0; i < tokenAddresses.length; ++i) {
            _setTokenPool(tokenAddresses[i], poolFeeTiers[i]);
        }
        emit SwappableTokensAdded(tokenAddresses);
    }

    /**
     * @dev Swap a token in the paymaster for ETH and deposit the amount received into the entry point
     * @param tokenAddress The token address of the token to swap
     * @param tokenAmount The amount of the token to swap
     * @param minEthAmountRecevied The minimum amount of ETH amount recevied post-swap
     * @notice only to be called by the owner of the contract.
     */
    function swapTokenAndDeposit(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 minEthAmountRecevied
    )
        external
        payable
        nonReentrant
    {
        // Swap tokens for WETH
        uint256 amountOut = _swapTokenToWeth(tokenAddress, tokenAmount, minEthAmountRecevied);
        if(amountOut > 0) {
            // Unwrap WETH to ETH
            _unwrapWeth(amountOut);
            // Deposit ETH into EP
            entryPoint.depositTo{ value: amountOut }(address(this));
        }
        emit TokensSwappedAndRefilledEntryPoint(tokenAddress, tokenAmount, amountOut, msg.sender);
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

    function setUniswapRouter(IV3SwapRouter uniswapRouterArg) external onlyOwner {
        _setUniswapRouter(uniswapRouterArg);
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
        uint256 tokenPrice,
        uint32 appliedPriceMarkup
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
                uint256(bytes32(userOp.paymasterAndData[_PAYMASTER_VALIDATION_GAS_OFFSET:_PAYMASTER_DATA_OFFSET])),
                userOp.preVerificationGas,
                userOp.gasFees,
                block.chainid,
                address(this),
                validUntil,
                validAfter,
                tokenAddress,
                tokenPrice,
                appliedPriceMarkup
            )
        );
    }

    /**
     * @dev Get the price of a token in USD
     * @param tokenAddress The address of the token to get the price of
     * @return price The price of the token in USD
     */
    function getPrice(address tokenAddress) public view returns (uint256) {
        return _getPrice(tokenAddress);
    }

    /**
     * @dev Check if a token is supported
     * @param tokenAddress The address of the token to check
     * @return bool True if the token is supported, false otherwise
     */
    function isTokenSupported(address tokenAddress) public view returns (bool) {
        return independentTokenDirectory[tokenAddress].oracle != IOracle(address(0));
    }

    /**
     * @dev Get the price markup for a token
     * @param tokenAddress The address of the token to get the price markup of
     * @return priceMarkup The price markup for the token
     */
    function independentPriceMarkup(address tokenAddress) public view returns (uint32) {
        return independentTokenDirectory[tokenAddress].priceMarkup;
    }

    /**
     * @dev Get the price expiry duration for a token
     * @param tokenAddress The address of the token to get the price expiry duration of
     * @return priceExpiryDuration The price expiry duration for the token
     */
    function independentPriceExpiryDuration(address tokenAddress) public view returns (uint256) {
        return independentTokenDirectory[tokenAddress].priceExpiryDuration;
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
        (PaymasterMode mode, bytes calldata modeSpecificData) = userOp.paymasterAndData.parsePaymasterAndData();

        if (uint8(mode) > 1) {
            revert InvalidPaymasterMode();
        }

        uint256 maxPenalty = (
            ( uint128(uint256(userOp.accountGasLimits))
                    + uint128(bytes16(userOp.paymasterAndData[_PAYMASTER_POSTOP_GAS_OFFSET:_PAYMASTER_DATA_OFFSET]))
                ) * 10 ) / 100;

        if (mode == PaymasterMode.EXTERNAL) {
            // Use the price and other params specified in modeSpecificData by the verifyingSigner
            // Useful for supporting tokens which don't have oracle support

            (
                uint48 validUntil,
                uint48 validAfter,
                address tokenAddress,
                uint256 tokenPrice,
                uint32 externalPriceMarkup,
                bytes memory signature
            ) = modeSpecificData.parseExternalModeSpecificData();

            if (signature.length != 64 && signature.length != 65) {
                revert InvalidSignatureLength();
            }

            bool validSig = verifyingSigner.isValidSignatureNow(
                ECDSA_solady.toEthSignedMessageHash(
                    getHash(userOp, validUntil, validAfter, tokenAddress, tokenPrice, externalPriceMarkup)
                ),
                signature
            );

            //don't revert on signature failure: return SIG_VALIDATION_FAILED
            if (!validSig) {
                return ("", _packValidationData(true, validUntil, validAfter));
            }

            context = abi.encode(
                userOp.sender,
                tokenAddress,
                maxPenalty,
                tokenPrice,
                externalPriceMarkup,
                userOpHash  
            );
            validationData = _packValidationData(false, validUntil, validAfter);
        
        /// INDEPENDENT MODE
        } else if (mode == PaymasterMode.INDEPENDENT) {

            address tokenAddress = modeSpecificData.parseIndependentModeSpecificData();
            
            // Use only oracles for the token specified in modeSpecificData
            if (modeSpecificData.length != 20) {
                revert InvalidTokenAddress();
            }

            context = abi.encode(
                userOp.sender,
                tokenAddress,
                maxPenalty,
                uint256(0), // pass 0, so we can check the price in _postOp and be 4337 compliant
                independentTokenDirectory[tokenAddress].priceMarkup,
                userOpHash
                );
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
        (
            address userOpSender,
            address tokenAddress,
            uint256 maxPenalty,
            uint256 tokenPrice,
            uint32 appliedPriceMarkup,
            bytes32 userOpHash
        ) = abi.decode(context, (address, address, uint256, uint256, uint32, bytes32));

        // If tokenPrice is 0, it means it was not set in the validatePaymasterUserOp => independent mode
        // So we need to get the price of the token from the oracle now
        if(tokenPrice == 0) {
            tokenPrice = _getPrice(tokenAddress);
            // if tokenPrice is still 0, it means the token is not supported
            if(tokenPrice == 0) {
                revert TokenNotSupported();
            }
        }

        // Calculate the amount to charge. unaccountedGas and maxPenalty are used, 
        // as we do not know the exact gas spent for postop and actual penalty at this point
        // this is obviously overcharge, however, the excess amount can be refunded by backend, 
        // when we know the exact gas spent (emitted by EP after executing UserOp)
        uint256 tokenAmount = (
            (actualGasCost + ((unaccountedGas + maxPenalty)) * actualUserOpFeePerGas)) * appliedPriceMarkup * tokenPrice
        / (_NATIVE_TOKEN_DECIMALS * _PRICE_DENOMINATOR);

        if (SafeTransferLib.trySafeTransferFrom(tokenAddress, userOpSender, address(this), tokenAmount)) {
            emit PaidGasInTokens(userOpSender, tokenAddress, actualGasCost, tokenAmount, appliedPriceMarkup, tokenPrice, userOpHash);
        } else {
            revert FailedToChargeTokens(userOpSender, tokenAddress, tokenAmount, userOpHash);
        }        
    }

    function _validateTokenInfo(TokenInfo memory tokenInfo) internal view {
        if (tokenInfo.oracle.decimals() != 8) {
            revert InvalidOracleDecimals();
        }
        if (tokenInfo.priceMarkup > _MAX_PRICE_MARKUP || tokenInfo.priceMarkup < _PRICE_DENOMINATOR) {
            revert InvalidPriceMarkup();
        }
        if (block.timestamp < tokenInfo.priceExpiryDuration) {
            revert InvalidPriceExpiryDuration();
        }
    }

    /// @notice Fetches the latest token price.
    /// @return price The latest token price fetched from the oracles.
    function _getPrice(address tokenAddress) internal view returns (uint256 price) {
        // Fetch token information from directory
        TokenInfo memory tokenInfo = independentTokenDirectory[tokenAddress];

        if (address(tokenInfo.oracle) == address(0)) {
            // If oracle not set, token isn't supported
            revert TokenNotSupported();
        }

        // Calculate price by using token and native oracle
        uint256 tokenPrice = _fetchPrice(tokenInfo.oracle, tokenInfo.priceExpiryDuration);
        uint256 nativeAssetPrice = _fetchPrice(nativeAssetToUsdOracle, _NATIVE_ASSET_PRICE_EXPIRY_DURATION);

        // Adjust to token  decimals
        price = (nativeAssetPrice * 10**IERC20Metadata(tokenAddress).decimals()) / tokenPrice;
    }

    /// @notice Fetches the latest price from the given oracle.
    /// @dev This function is used to get the latest price from the tokenOracle or nativeAssetToUsdOracle.
    /// @param oracle The oracle contract to fetch the price from.
    /// @return price The latest price fetched from the oracle.
    /// Note: We could do this using oracle aggregator, so we can also use Pyth. or Twap based oracle and just not chainlink.
    function _fetchPrice(IOracle oracle, uint256 priceExpiryDuration) internal view returns (uint256 price) {
        (, int256 answer,, uint256 updatedAt,) = oracle.latestRoundData();
        if (answer <= 0) {
            revert OraclePriceNotPositive();
        }
        if (updatedAt < block.timestamp - priceExpiryDuration) {
            revert OraclePriceExpired();
        }
        price = uint256(answer);
    }

    function _withdrawERC20(IERC20 token, address target, uint256 amount) private {
        if (target == address(0)) revert CanNotWithdrawToZeroAddress();
        SafeTransferLib.safeTransfer(address(token), target, amount);
        emit TokensWithdrawn(address(token), target, amount, msg.sender);
    }
}
