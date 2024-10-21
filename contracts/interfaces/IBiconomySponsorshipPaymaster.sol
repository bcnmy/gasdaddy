// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PackedUserOperation } from "account-abstraction/core/UserOperationLib.sol";

interface IBiconomySponsorshipPaymaster {

    struct WithdrawalRequest {
        uint256 amount;
        address to;
        uint256 requestSubmittedTimestamp;
    } 

    event UnaccountedGasChanged(uint256 indexed oldValue, uint256 indexed newValue);
    event FixedPriceMarkupChanged(uint256 indexed oldValue, uint256 indexed newValue);
    event VerifyingSignerChanged(address indexed oldSigner, address indexed newSigner, address indexed actor);
    event FeeCollectorChanged(address indexed oldFeeCollector, address indexed newFeeCollector, address indexed actor);
    event GasDeposited(address indexed _paymasterId, uint256 indexed _value);
    event GasWithdrawn(address indexed _paymasterId, address indexed _to, uint256 indexed _value);
    event GasBalanceDeducted(address indexed _paymasterId, uint256 indexed _charge, uint256 indexed _premium);
    event Received(address indexed sender, uint256 value);
    event TokensWithdrawn(address indexed token, address indexed to, uint256 indexed amount, address actor);
    event WithdrawalRequestSubmitted(address withdrawAddress, uint256 amount);

    function depositFor(address paymasterId) external payable;

    function setSigner(address newVerifyingSigner) external payable;

    function setFeeCollector(address newFeeCollector) external payable;

    function setUnaccountedGas(uint256 value) external payable;

    function withdrawERC20(IERC20 token, address target, uint256 amount) external;

    function withdrawEth(address payable recipient, uint256 amount) external payable;

    function getBalance(address paymasterId) external view returns (uint256 balance);

    function getHash(
        PackedUserOperation calldata userOp,
        address paymasterId,
        uint48 validUntil,
        uint48 validAfter,
        uint32 priceMarkup
    )
        external
        view
        returns (bytes32);

    function parsePaymasterAndData(
        bytes calldata paymasterAndData
    )
        external
        pure
        returns (
            address paymasterId,
            uint48 validUntil,
            uint48 validAfter,
            uint32 priceMarkup,
            uint128 paymasterValidationGasLimit,
            uint128 paymasterPostOpGasLimit,
            bytes calldata signature
        );
}
