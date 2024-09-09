// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IEntryPoint } from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import { PackedUserOperation, UserOperationLib } from "@account-abstraction/contracts/core/UserOperationLib.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";
import { BasePaymaster } from "../base/BasePaymaster.sol";
import { BiconomyTokenPaymasterErrors } from "../common/BiconomyTokenPaymasterErrors.sol";
import { IBiconomyTokenPaymaster } from "../interfaces/IBiconomyTokenPaymaster.sol";
import { IOracle } from "../interfaces/oracles/IOracle.sol";
import "@account-abstraction/contracts/core/Helpers.sol";

/**
 * @title BiconomyTokenPaymaster
 * @author ShivaanshK<shivaansh.kapoor@biconomy.io>
 * @author livingrockrises<chirag@biconomy.io>
 * @notice Token Paymaster for Entry Point v0.7
 * @dev  A paymaster that allows user to pay gas fees in ERC20 tokens. The paymaster owner chooses which tokens to
 * accept. The payment manager (usually the owner) first deposits native gas into the EntryPoint. Then, for each
 * transaction, it takes the gas fee from the user's ERC20 token balance. The exchange rate between ETH and the token is
 * calculated using 1 of three methods: external price source, off-chain oracle, or a TWAP oracle.
 */
contract BiconomyTokenPaymaster is
    BasePaymaster,
    ReentrancyGuardTransient,
    BiconomyTokenPaymasterErrors,
    IBiconomyTokenPaymaster
{
    using UserOperationLib for PackedUserOperation;

    // State variables
    address public feeCollector;
    uint256 public unaccountedGas;
    uint256 public dynamicAdjustment;
    IOracle public nativeOracle; // ETH -> USD price
    mapping(address => TokenInfo) tokenDirectory;

    // Limit for unaccounted gas cost
    uint256 private constant UNACCOUNTED_GAS_LIMIT = 50_000;
    uint256 private constant PRICE_DENOMINATOR = 1e6;
    uint256 private constant MAX_DYNAMIC_ADJUSTMENT = 2e6;

    constructor(
        address _owner,
        IEntryPoint _entryPoint,
        uint256 _unaccountedGas,
        uint256 _dynamicAdjustment,
        IOracle _nativeOracle,
        address[] memory _tokens, // Array of token addresses
        uint8[] memory _decimals, // Array of corresponding token decimals
        IOracle[] memory _oracles // Array of corresponding oracle addresses
    )
        BasePaymaster(_owner, _entryPoint)
    {
        if (_unaccountedGas > UNACCOUNTED_GAS_LIMIT) {
            revert UnaccountedGasTooHigh();
        } else if (_dynamicAdjustment > MAX_DYNAMIC_ADJUSTMENT || _dynamicAdjustment == 0) {
            revert InvalidDynamicAdjustment();
        } else if (_tokens.length != _oracles.length || _tokens.length != _decimals.length) {
            revert TokensAndInfoLengthMismatch();
        }
        assembly ("memory-safe") {
            sstore(feeCollector.slot, address()) // initialize fee collector to this contract
            sstore(unaccountedGas.slot, _unaccountedGas)
            sstore(dynamicAdjustment.slot, _dynamicAdjustment)
            sstore(nativeOracle.slot, _nativeOracle)
        }

        // Populate the tokenToOracle mapping
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenDirectory[_tokens[i]] = TokenInfo(_oracles[i], _decimals[i]);
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
        emit FeeCollectorChanged(oldFeeCollector, _newFeeCollector, msg.sender);
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
        emit UnaccountedGasChanged(oldUnaccountedGas, _newUnaccountedGas);
    }

    /**
     * @dev Set a new dynamicAdjustment value.
     * @param _newDynamicAdjustment The new value to be set as the unaccounted gas value
     * @notice only to be called by the owner of the contract.
     */
    function setDynamicAdjustment(uint256 _newDynamicAdjustment) external payable override onlyOwner {
        if (_newDynamicAdjustment > MAX_DYNAMIC_ADJUSTMENT || _newDynamicAdjustment == 0) {
            revert InvalidDynamicAdjustment();
        }
        uint256 oldDynamicAdjustment = dynamicAdjustment;
        assembly ("memory-safe") {
            sstore(dynamicAdjustment.slot, _newDynamicAdjustment)
        }
        emit FixedDynamicAdjustmentChanged(oldDynamicAdjustment, _newDynamicAdjustment);
    }

    /**
     * @dev Set or update a TokenInfo entry in the tokenDirectory mapping.
     * @param _tokenAddress The new value to be set as the unaccounted gas value
     * @param _oracle The new value to be set as the unaccounted gas value
     * @param _decimals The new value to be set as the unaccounted gas value
     * @notice only to be called by the owner of the contract.
     */
    function setTokenInfo(
        address _tokenAddress,
        IOracle _oracle,
        uint8 _decimals
    )
        external
        payable
        override
        onlyOwner
    {
        tokenDirectory[_tokenAddress] = TokenInfo(_oracle, _decimals);
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
    { }

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
        (context);
        // Implementation of post-operation logic
    }

    function _withdrawERC20(IERC20 token, address target, uint256 amount) private {
        if (target == address(0)) revert CanNotWithdrawToZeroAddress();
        SafeTransferLib.safeTransfer(address(token), target, amount);
    }

    /// @notice Fetches the latest token price.

    /// @return price The latest token price fetched from the oracles.
    function getPrice(address tokenAddress) internal view returns (uint192) {
        TokenInfo memory tokenInfo = tokenDirectory[tokenAddress];
        uint192 tokenPrice = _fetchPrice(tokenInfo.oracle);
        uint192 nativeAssetPrice = _fetchPrice(nativeOracle);
        uint192 price = nativeAssetPrice * uint192(tokenInfo.decimals) / tokenPrice;
        return price;
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
        // if (updatedAt < block.timestamp - stalenessThreshold) {
        //     revert OraclePriceStale();
        // }
        price = uint192(int192(answer));
    }
}
