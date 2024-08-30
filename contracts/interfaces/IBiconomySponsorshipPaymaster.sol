// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PackedUserOperation } from "@account-abstraction/contracts/core/UserOperationLib.sol";

interface IBiconomySponsorshipPaymaster{
    event UnaccountedGasChanged(uint256 indexed oldValue, uint256 indexed newValue);
    event FixedDynamicAdjustmentChanged(uint32 indexed oldValue, uint32 indexed newValue);
    event VerifyingSignerChanged(address indexed oldSigner, address indexed newSigner, address indexed actor);
    event FeeCollectorChanged(address indexed oldFeeCollector, address indexed newFeeCollector, address indexed actor);
    event GasDeposited(address indexed paymasterId, uint256 indexed value);
    event GasWithdrawn(address indexed paymasterId, address indexed to, uint256 indexed value);
    event GasBalanceDeducted(address indexed paymasterId, uint256 indexed charge, bytes32 indexed userOpHash);
    event DynamicAdjustmentCollected(address indexed paymasterId, uint256 indexed dynamicAdjustment);
    event Received(address indexed sender, uint256 value);
    event TokensWithdrawn(address indexed token, address indexed to, uint256 indexed amount, address actor);

    function depositFor(address paymasterId) external payable;

    function setSigner(address _newVerifyingSigner) external payable;

    function setFeeCollector(address _newFeeCollector) external payable;

    function setUnaccountedGas(uint48 value) external payable;

    function withdrawERC20(IERC20 token, address target, uint256 amount) external;

    function withdrawEth(address payable recipient, uint256 amount) external payable;

    function getBalance(address paymasterId) external view returns (uint256 balance);

    function getHash(
        PackedUserOperation calldata userOp,
        address paymasterId,
        uint48 validUntil,
        uint48 validAfter,
        uint32 dynamicAdjustment
    )
        external
        view
        returns (bytes32);

    function parsePaymasterAndData(bytes calldata paymasterAndData)
        external
        pure
        returns (
            address paymasterId,
            uint48 validUntil,
            uint48 validAfter,
            uint32 dynamicAdjustment,
            bytes calldata signature
        );
}
