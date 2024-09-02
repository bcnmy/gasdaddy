// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IBiconomyTokenPaymaster {
    enum PriceSource {
        EXTERNAL,
        ORACLE
    }

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


    function setSigner(address _newVerifyingSigner) external payable;

    function setFeeCollector(address _newFeeCollector) external payable;

    function setUnaccountedGas(uint16 value) external payable;
}
