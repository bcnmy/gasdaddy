// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

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
        uint32 priceMarkup;
        uint256 priceExpiryDuration;
    }

    event UpdatedUnaccountedGas(uint256 indexed oldValue, uint256 indexed newValue);
    event UpdatedFixedPriceMarkup(uint32 indexed oldValue, uint32 indexed newValue);
    event UpdatedVerifyingSigner(address indexed oldSigner, address indexed newSigner, address indexed actor);
    event UpdatedFeeCollector(address indexed oldFeeCollector, address indexed newFeeCollector, address indexed actor);
    event UpdatedPriceExpiryDuration(uint256 indexed oldValue, uint256 indexed newValue);
    
    event PaidGasInTokens(
        address indexed userOpSender,
        address indexed token,
        uint256 gasCostBeforePostOpAndPenalty,
        uint256 tokenCharge,
        uint32 priceMarkup,
        uint256 tokenPrice,
        bytes32 userOpHash
    );
    
    event EthWithdrawn(address indexed recipient, uint256 indexed amount);

    event Received(address indexed sender, uint256 value);
    event TokensWithdrawn(address indexed token, address indexed to, uint256 indexed amount, address actor);
    event AddedToTokenDirectory(address indexed tokenAddress, IOracle indexed oracle, uint8 decimals);
    event RemovedFromTokenDirectory(address indexed tokenAddress);
    event UpdatedNativeAssetOracle(IOracle indexed oldOracle, IOracle indexed newOracle);
    event TokensSwappedAndRefilledEntryPoint(address indexed tokenAddress, uint256 indexed tokenAmount, uint256 indexed amountOut, address actor);
    event SwappableTokensAdded(address[] indexed tokenAddresses);

    function setSigner(address newVerifyingSigner) external payable;

    function setUnaccountedGas(uint256 value) external payable;

    function setPriceMarkupForToken(address tokenAddress, uint32 newPriceMarkup) external payable;

    function setPriceExpiryDurationForToken(address tokenAddress, uint256 newPriceExpiryDuration) external payable;

    function setNativeAssetToUsdOracle(IOracle oracle) external payable;

    function addToTokenDirectory(address tokenAddress, TokenInfo memory tokenInfo) external payable;
}
