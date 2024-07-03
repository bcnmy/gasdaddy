// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IBiconomySponsorshipPaymaster {
    event PostopCostChanged(uint256 indexed oldValue, uint256 indexed newValue);
    event FixedPriceMarkupChanged(uint32 indexed oldValue, uint32 indexed newValue);

    event VerifyingSignerChanged(address indexed oldSigner, address indexed newSigner, address indexed actor);

    event FeeCollectorChanged(address indexed oldFeeCollector, address indexed newFeeCollector, address indexed actor);
    event GasDeposited(address indexed paymasterId, uint256 indexed value);
    event GasWithdrawn(address indexed paymasterId, address indexed to, uint256 indexed value);
    event GasBalanceDeducted(address indexed paymasterId, uint256 indexed charge, bytes32 indexed userOpHash);
    event PremiumCollected(address indexed paymasterId, uint256 indexed premium);
    event Received(address indexed sender, uint256 value);
    event TokensWithdrawn(address indexed token, address indexed to, uint256 indexed amount, address actor);
}
