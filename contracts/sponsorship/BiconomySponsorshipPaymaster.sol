// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

/* solhint-disable reason-string */

import "../base/BasePaymaster.sol";
import "account-abstraction/core/UserOperationLib.sol";
import "account-abstraction/core/Helpers.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";
import { ECDSA as ECDSA_solady } from "solady/utils/ECDSA.sol";
import { BiconomySponsorshipPaymasterErrors } from "../common/BiconomySponsorshipPaymasterErrors.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IBiconomySponsorshipPaymaster } from "../interfaces/IBiconomySponsorshipPaymaster.sol";

/**
 * @title BiconomySponsorshipPaymaster
 * @author livingrockrises<chirag@biconomy.io>
 * @author ShivaanshK<shivaansh.kapoor@biconomy.io>
 * @notice Based on Infinitism's 'VerifyingPaymaster' contract
 * @dev This contract is used to sponsor the transaction fees of the user operations
 * Uses a verifying signer to provide the signature if predetermined conditions are met
 * regarding the user operation calldata. Also this paymaster is Singleton in nature which
 * means multiple Dapps/Wallet clients willing to sponsor the transactions can share this paymaster.
 * Maintains it's own accounting of the gas balance for each Dapp/Wallet client
 * and Manages it's own deposit on the EntryPoint.
 */

// @Todo: Add more methods in interface

contract BiconomySponsorshipPaymaster is
    BasePaymaster,
    ReentrancyGuardTransient,
    BiconomySponsorshipPaymasterErrors,
    IBiconomySponsorshipPaymaster
{
    using UserOperationLib for PackedUserOperation;
    using SignatureCheckerLib for address;
    using ECDSA_solady for bytes32;

    address public verifyingSigner;
    address public feeCollector;
    uint256 public unaccountedGas;

    // Denominator to prevent precision errors when applying price markup
    uint256 private constant PRICE_DENOMINATOR = 1e6;
    // Offset in PaymasterAndData to get to PAYMASTER_ID_OFFSET
    uint256 private constant PAYMASTER_ID_OFFSET = PAYMASTER_DATA_OFFSET;
    // Limit for unaccounted gas cost
    // Review cap
    uint256 private constant UNACCOUNTED_GAS_LIMIT = 100_000;

    mapping(address => uint256) public paymasterIdBalances;

    constructor(
        address _owner,
        IEntryPoint _entryPoint,
        address _verifyingSigner,
        address _feeCollector,
        uint256 _unaccountedGas
    )
        BasePaymaster(_owner, _entryPoint)
    {
        _checkConstructorArgs(_verifyingSigner, _feeCollector, _unaccountedGas);
        assembly ("memory-safe") {
            sstore(verifyingSigner.slot, _verifyingSigner)
        }
        feeCollector = _feeCollector;
        unaccountedGas = _unaccountedGas;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /**
     * @dev Add a deposit for this paymaster and given paymasterId (Dapp Depositor address), used for paying for
     * transaction fees
     * @param paymasterId dapp identifier for which deposit is being made
     */
    function depositFor(address paymasterId) external payable nonReentrant {
        if (paymasterId == address(0)) revert PaymasterIdCanNotBeZero();
        if (msg.value == 0) revert DepositCanNotBeZero();
        paymasterIdBalances[paymasterId] += msg.value;
        entryPoint.depositTo{ value: msg.value }(address(this));
        emit GasDeposited(paymasterId, msg.value);
    }

    /**
     * @dev Set a new verifying signer address.
     * Can only be called by the owner of the contract.
     * @param _newVerifyingSigner The new address to be set as the verifying signer.
     * @notice If _newVerifyingSigner is set to zero address, it will revert with an error.
     * After setting the new signer address, it will emit an event VerifyingSignerChanged.
     */
    function setSigner(address _newVerifyingSigner) external payable onlyOwner {
        if (_isContract(_newVerifyingSigner)) revert VerifyingSignerCanNotBeContract();
        if (_newVerifyingSigner == address(0)) {
            revert VerifyingSignerCanNotBeZero();
        }
        address oldSigner = verifyingSigner;
        assembly ("memory-safe") {
            sstore(verifyingSigner.slot, _newVerifyingSigner)
        }
        emit VerifyingSignerChanged(oldSigner, _newVerifyingSigner, msg.sender);
    }

    /**
     * @dev Set a new fee collector address.
     * Can only be called by the owner of the contract.
     * @param _newFeeCollector The new address to be set as the fee collector.
     * @notice If _newFeeCollector is set to zero address, it will revert with an error.
     * After setting the new fee collector address, it will emit an event FeeCollectorChanged.
     */
    function setFeeCollector(address _newFeeCollector) external payable override onlyOwner {
        if (_isContract(_newFeeCollector)) revert FeeCollectorCanNotBeContract();
        if (_newFeeCollector == address(0)) revert FeeCollectorCanNotBeZero();
        address oldFeeCollector = feeCollector;
        feeCollector = _newFeeCollector;
        emit FeeCollectorChanged(oldFeeCollector, _newFeeCollector, msg.sender);
    }

    /**
     * @dev Set a new unaccountedEPGasOverhead value.
     * @param value The new value to be set as the unaccountedEPGasOverhead.
     * @notice only to be called by the owner of the contract.
     */
    function setUnaccountedGas(uint256 value) external payable onlyOwner {
        if (value > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
        uint256 oldValue = unaccountedGas;
        unaccountedGas = value;
        emit UnaccountedGasChanged(oldValue, value);
    }

    /**
     * @dev Override the default implementation.
     */
    function deposit() external payable virtual override {
        revert UseDepositForInstead();
    }

    /**
     * @dev pull tokens out of paymaster in case they were sent to the paymaster at any point.
     * @param token the token deposit to withdraw
     * @param target address to send to
     * @param amount amount to withdraw
     */
    function withdrawERC20(IERC20 token, address target, uint256 amount) external onlyOwner nonReentrant {
        _withdrawERC20(token, target, amount);
    }

    /**
     * @dev Withdraws the specified amount of gas tokens from the paymaster's balance and transfers them to the
     * specified address.
     * @param withdrawAddress The address to which the gas tokens should be transferred.
     * @param amount The amount of gas tokens to withdraw.
     */
    function withdrawTo(address payable withdrawAddress, uint256 amount) external override nonReentrant {
        if (withdrawAddress == address(0)) revert CanNotWithdrawToZeroAddress();
        uint256 currentBalance = paymasterIdBalances[msg.sender];
        if (amount > currentBalance) {
            revert InsufficientFundsInGasTank();
        }
        paymasterIdBalances[msg.sender] = currentBalance - amount;
        entryPoint.withdrawTo(withdrawAddress, amount);
        emit GasWithdrawn(msg.sender, withdrawAddress, amount);
    }

    function withdrawEth(address payable recipient, uint256 amount) external payable onlyOwner nonReentrant {
        (bool success,) = recipient.call{ value: amount }("");
        if (!success) {
            revert WithdrawalFailed();
        }
    }

    /**
     * @dev get the current deposit for paymasterId (Dapp Depositor address)
     * @param paymasterId dapp identifier
     */
    function getBalance(address paymasterId) external view returns (uint256 balance) {
        balance = paymasterIdBalances[paymasterId];
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
        address paymasterId,
        uint48 validUntil,
        uint48 validAfter,
        uint32 priceMarkup
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
                paymasterId,
                validUntil,
                validAfter,
                priceMarkup
            )
        );
    }

    function parsePaymasterAndData(bytes calldata paymasterAndData)
        public
        pure
        returns (
            address paymasterId,
            uint48 validUntil,
            uint48 validAfter,
            uint32 priceMarkup,
            bytes calldata signature
        )
    {
        unchecked {
            paymasterId = address(bytes20(paymasterAndData[PAYMASTER_ID_OFFSET:PAYMASTER_ID_OFFSET + 20]));
            validUntil = uint48(bytes6(paymasterAndData[PAYMASTER_ID_OFFSET + 20:PAYMASTER_ID_OFFSET + 26]));
            validAfter = uint48(bytes6(paymasterAndData[PAYMASTER_ID_OFFSET + 26:PAYMASTER_ID_OFFSET + 32]));
            priceMarkup = uint32(bytes4(paymasterAndData[PAYMASTER_ID_OFFSET + 32:PAYMASTER_ID_OFFSET + 36]));
            signature = paymasterAndData[PAYMASTER_ID_OFFSET + 36:];
        }
    }

    /// @notice Performs post-operation tasks, such as deducting the sponsored gas cost from the paymasterId's balance
    /// @dev This function is called after a user operation has been executed or reverted.
    /// @param context The context containing the token amount and user sender address.
    /// @param actualGasCost The actual gas cost of the transaction.
    function _postOp(
        PostOpMode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    )
        internal
        override
    {
        unchecked {
            (address paymasterId, uint32 priceMarkup, bytes32 userOpHash, uint256 prechargedAmount) =
                abi.decode(context, (address, uint32, bytes32, uint256));

            // Include unaccountedGas since EP doesn't include this in actualGasCost
            // unaccountedGas = postOpGas + EP overhead gas + estimated penalty
            actualGasCost = actualGasCost + (unaccountedGas * actualUserOpFeePerGas);
            // Apply the price markup
            uint256 adjustedGasCost = (actualGasCost * priceMarkup) / PRICE_DENOMINATOR;

            if (prechargedAmount > adjustedGasCost) {
                // If overcharged refund the excess
                paymasterIdBalances[paymasterId] += (prechargedAmount - adjustedGasCost);
            }

            // Should always be true
            // if (adjustedGasCost > actualGasCost) {
            // Apply priceMarkup to fee collector balance
            uint256 premium = adjustedGasCost - actualGasCost;
            paymasterIdBalances[feeCollector] += premium;
            // Review:  if we should emit adjustedGasCost as well
            emit PriceMarkupCollected(paymasterId, premium);
            // }

            // Review: emit min required information
            emit GasBalanceDeducted(paymasterId, adjustedGasCost, userOpHash);
        }
    }

    /**
     * verify our external signer signed this request.
     * the "paymasterAndData" is expected to be the paymaster and a signature over the entire request params
     * paymasterAndData[:20] : address(this)
     * paymasterAndData[52:72] : paymasterId (dappDepositor)
     * paymasterAndData[72:78] : validUntil
     * paymasterAndData[78:84] : validAfter
     * paymasterAndData[84:88] : priceMarkup
     * paymasterAndData[88:] : signature
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 requiredPreFund
    )
        internal
        override
        returns (bytes memory context, uint256 validationData)
    {
        (address paymasterId, uint48 validUntil, uint48 validAfter, uint32 priceMarkup, bytes calldata signature)
        = parsePaymasterAndData(userOp.paymasterAndData);
        //ECDSA library supports both 64 and 65-byte long signatures.
        // we only "require" it here so that the revert reason on invalid signature will be of "VerifyingPaymaster", and
        // not "ECDSA"
        if (signature.length != 64 && signature.length != 65) {
            revert InvalidSignatureLength();
        }

        if(unaccountedGas >= userOp.unpackPostOpGasLimit()) {
            revert PostOpGasLimitTooLow();
        } 

        bool validSig = ((getHash(userOp, paymasterId, validUntil, validAfter, priceMarkup).toEthSignedMessageHash()).tryRecover(signature)) == verifyingSigner ? true : false;

        //don't revert on signature failure: return SIG_VALIDATION_FAILED
        if (!validSig) {
            return ("", _packValidationData(true, validUntil, validAfter));
        }

        // Send 1e6 for No markup
        if (priceMarkup > 2e6 || priceMarkup < 1e6) {
            revert InvalidPriceMarkup();
        }

        // Deduct the max gas cost.
        uint256 effectiveCost = (requiredPreFund + unaccountedGas * userOp.unpackMaxFeePerGas()) * priceMarkup / PRICE_DENOMINATOR;

        if (effectiveCost > paymasterIdBalances[paymasterId]) {
            revert InsufficientFundsForPaymasterId();
        }

        paymasterIdBalances[paymasterId] -= effectiveCost;

        context = abi.encode(paymasterId, priceMarkup, userOpHash, effectiveCost);

        //no need for other on-chain validation: entire UserOp should have been checked
        // by the external service prior to signing it.
        return (context, _packValidationData(false, validUntil, validAfter));
    }

    function _checkConstructorArgs(
        address _verifyingSigner,
        address _feeCollector,
        uint256 _unaccountedGas
    )
        internal
        view
    {
        if (_verifyingSigner == address(0)) {
            revert VerifyingSignerCanNotBeZero();
        } else if (_isContract(_verifyingSigner)) {
            revert VerifyingSignerCanNotBeContract();
        } else if (_feeCollector == address(0)) {
            revert FeeCollectorCanNotBeZero();
        } else if (_isContract(_feeCollector)) {
            revert FeeCollectorCanNotBeContract();
        } else if (_unaccountedGas > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
    }

    function _withdrawERC20(IERC20 token, address target, uint256 amount) private {
        if (target == address(0)) revert CanNotWithdrawToZeroAddress();
        SafeTransferLib.safeTransfer(address(token), target, amount);
        emit TokensWithdrawn(address(token), target, amount, msg.sender);
    }
}
