// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBiconomySponsorshipPaymaster {
    event PostopCostChanged(uint256 indexed _oldValue, uint256 indexed _newValue);
    event FixedPriceMarkupChanged(uint32 indexed _oldValue, uint32 indexed _newValue);

    event VerifyingSignerChanged(address indexed _oldSigner, address indexed _newSigner, address indexed _actor);

    event FeeCollectorChanged(
        address indexed _oldFeeCollector, address indexed _newFeeCollector, address indexed _actor
    );
    event GasDeposited(address indexed _paymasterId, uint256 indexed _value);
    event GasWithdrawn(address indexed _paymasterId, address indexed _to, uint256 indexed _value);
    event GasBalanceDeducted(address indexed _paymasterId, uint256 indexed _charge, bytes32 indexed userOpHash);
    event PremiumCollected(address indexed _paymasterId, uint256 indexed _premium);
    event Received(address indexed sender, uint256 value);
    event TokensWithdrawn(address indexed _token, address indexed _to, uint256 indexed _amount, address actor);
}