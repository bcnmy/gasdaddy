// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import { IOracle } from "./oracles/IOracle.sol";

interface IBiconomyTokenPaymaster {
    // Modes that paymaster can be used in
    enum PaymasterMode {
        EXTERNAL, // Price provided by external service. Authenticated using signature from verifyingSigner
        INDEPENDENT // Price queried from oracle. No signature needed from external service.

    }

    // Struct for storing information about the token
    struct TokenInfo {
        IOracle oracle;
        uint256 decimals;
    }

    event UpdatedUnaccountedGas(uint256 indexed oldValue, uint256 indexed newValue);
    event UpdatedFixedDynamicAdjustment(uint256 indexed oldValue, uint256 indexed newValue);
    event UpdatedVerifyingSigner(address indexed oldSigner, address indexed newSigner, address indexed actor);
    event UpdatedFeeCollector(address indexed oldFeeCollector, address indexed newFeeCollector, address indexed actor);
    event UpdatedPriceExpiryDuration(uint256 indexed oldValue, uint256 indexed newValue);
    event GasDeposited(address indexed paymasterId, uint256 indexed value);
    event GasWithdrawn(address indexed paymasterId, address indexed to, uint256 indexed value);
    event GasBalanceDeducted(address indexed paymasterId, uint256 indexed charge, bytes32 indexed userOpHash);
    event DynamicAdjustmentCollected(address indexed paymasterId, uint256 indexed dynamicAdjustment);
    event Received(address indexed sender, uint256 value);
    event TokensWithdrawn(address indexed token, address indexed to, uint256 indexed amount, address actor);
    event UpdatedTokenDirectory(address indexed tokenAddress, IOracle indexed oracle, uint8 decimals);
    event UpdatedNativeAssetOracle(IOracle indexed oldOracle, IOracle indexed newOracle);

    function setSigner(address _newVerifyingSigner) external payable;

    function setFeeCollector(address _newFeeCollector) external payable;

    function setUnaccountedGas(uint256 value) external payable;

    function setDynamicAdjustment(uint256 _newUnaccountedGas) external payable;

    function setPriceExpiryDuration(uint256 _newPriceExpiryDuration) external payable;

    function setNativeOracle(IOracle _oracle) external payable;

    function updateTokenDirectory(address _tokenAddress, IOracle _oracle) external payable;
}
