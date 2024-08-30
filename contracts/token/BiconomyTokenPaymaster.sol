// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import { ECDSA as ECDSA_solady } from "@solady/src/utils/ECDSA.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IEntryPoint } from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import { SignatureCheckerLib } from "@solady/src/utils/SignatureCheckerLib.sol";
import { PackedUserOperation, UserOperationLib } from "@account-abstraction/contracts/core/UserOperationLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";
import { BasePaymaster } from "../base/BasePaymaster.sol";
import { BiconomyTokenPaymasterErrors } from "../common/BiconomyTokenPaymasterErrors.sol";
import { IBiconomyTokenPaymaster } from "../interfaces/IBiconomyTokenPaymaster.sol";

/**
 * @title BiconomyTokenPaymaster
 * @author ShivaanshK<shivaansh.kapoor@biconomy.io>
 * @author livingrockrises<chirag@biconomy.io>
 * @notice Token Paymaster for Entry Point v0.7
 * @dev  A paymaster that allows user to pay gas fee in ERC20 tokens. The paymaster owner chooses which tokens to
 * accept. The payment manager (usually the owner) first deposits native gas into the EntryPoint. Then, for each
 * transaction, it takes the gas fee from the user's ERC20 token balance. The exchange rate between ETH and the token is
 * calculated using 1 of three methods: external price source, off-chain oracle, or a TWAP oracle.
 */
contract BiconomyTokenPaymaster is
    BasePaymaster,
    ReentrancyGuard,
    BiconomyTokenPaymasterErrors,
    IBiconomyTokenPaymaster
{
    using UserOperationLib for PackedUserOperation;
    using SignatureCheckerLib for address;

    address public verifyingSigner;
    address public feeCollector;
    uint16 public unaccountedGas;

    // Limit for unaccounted gas cost
    uint16 private constant UNACCOUNTED_GAS_LIMIT = 50_000;

    constructor(
        address _owner,
        IEntryPoint _entryPoint,
        address _verifyingSigner,
        uint16 _unaccountedGas
    )
        BasePaymaster(_owner, _entryPoint)
    {
        _checkConstructorArgs(_verifyingSigner, _unaccountedGas);
        assembly ("memory-safe") {
            sstore(verifyingSigner.slot, _verifyingSigner)
        }
        verifyingSigner = _verifyingSigner;
        feeCollector = address(this); // initialize fee collector to this contract
        unaccountedGas = _unaccountedGas;
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
    function setUnaccountedGas(uint16 value) external payable override onlyOwner {
        if (value > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
        uint16 oldValue = unaccountedGas;
        unaccountedGas = value;
        emit UnaccountedGasChanged(oldValue, value);
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
        // Implementation of user operation validation logic
    }

    /**
     * @dev Post-operation handler.
     * This method is abstract in BasePaymaster and must be implemented in derived contracts.
     * @param mode The mode of the post operation (opSucceeded, opReverted, or postOpReverted).
     * @param context The context value returned by validatePaymasterUserOp.
     * @param actualGasCost Actual gas used so far (excluding this postOp call).
     * @param actualUserOpFeePerGas The gas price this UserOp pays.
     */
    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    )
        internal
        override
    {
        // Implementation of post-operation logic
    }

    function _checkConstructorArgs(address _verifyingSigner, uint16 _unaccountedGas) internal view {
        if (_verifyingSigner == address(0)) {
            revert VerifyingSignerCanNotBeZero();
        } else if (_isContract(_verifyingSigner)) {
            revert VerifyingSignerCanNotBeContract();
        } else if (_unaccountedGas > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
    }

    function _withdrawERC20(IERC20 token, address target, uint256 amount) private {
        if (target == address(0)) revert CanNotWithdrawToZeroAddress();
        SafeTransferLib.safeTransfer(address(token), target, amount);
    }
}
