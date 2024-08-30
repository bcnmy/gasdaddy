// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import { ECDSA as ECDSA_solady } from "@solady/src/utils/ECDSA.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IEntryPoint } from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import { SignatureCheckerLib } from "@solady/src/utils/SignatureCheckerLib.sol";
import { PackedUserOperation, UserOperationLib } from "@account-abstraction/contracts/core/UserOperationLib.sol";
import { BasePaymaster } from "../base/BasePaymaster.sol";
import { BiconomyTokenPaymasterErrors } from "../common/BiconomyTokenPaymasterErrors.sol";
import { IBiconomyTokenPaymaster } from "../interfaces/IBiconomyTokenPaymaster.sol";

/**
 * @title BiconomyTokenPaymaster
 * @author ShivaanshK<shivaansh.kapoor@biconomy.io>
 * @author livingrockrises<chirag@biconomy.io>
 * @notice Token Paymaster for v0.7 Entry Point
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
        address _feeCollector,
        uint16 _unaccountedGas
    )
        BasePaymaster(_owner, _entryPoint)
    {
        _checkConstructorArgs(_verifyingSigner, _feeCollector, _unaccountedGas);
        assembly ("memory-safe") {
            sstore(verifyingSigner.slot, _verifyingSigner)
        }
        verifyingSigner = _verifyingSigner;
        feeCollector = _feeCollector;
        unaccountedGas = _unaccountedGas;
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
    function setUnaccountedGas(uint16 value) external payable override onlyOwner {
        if (value > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        }
        uint16 oldValue = unaccountedGas;
        unaccountedGas = value;
        emit UnaccountedGasChanged(oldValue, value);
    }

    /**
     * Add a deposit in native currency for this paymaster, used for paying for transaction fees.
     * This is ideally done by the entity who is managing the received ERC20 gas tokens.
     */
    function deposit() public payable virtual override nonReentrant {
        entryPoint.depositTo{ value: msg.value }(address(this));
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

    function _checkConstructorArgs(
        address _verifyingSigner,
        address _feeCollector,
        uint16 _unaccountedGas
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
}
