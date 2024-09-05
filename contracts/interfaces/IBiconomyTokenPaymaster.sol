// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IBiconomyTokenPaymaster {
    event UnaccountedGasChanged(uint256 indexed oldValue, uint256 indexed newValue);
    event FixedDynamicAdjustmentChanged(uint32 indexed oldValue, uint32 indexed newValue);
    event FeeCollectorChanged(address indexed oldFeeCollector, address indexed newFeeCollector, address indexed actor);
    event GasDeposited(address indexed paymasterId, uint256 indexed value);
    event GasWithdrawn(address indexed paymasterId, address indexed to, uint256 indexed value);
    event GasBalanceDeducted(address indexed paymasterId, uint256 indexed charge, bytes32 indexed userOpHash);
    event DynamicAdjustmentCollected(address indexed paymasterId, uint256 indexed dynamicAdjustment);
    event Received(address indexed sender, uint256 value);
    event TokensWithdrawn(address indexed token, address indexed to, uint256 indexed amount, address actor);

    function setFeeCollector(address _newFeeCollector) external payable;

    function setUnaccountedGas(uint256 value) external payable;

    function setDynamicAdjustment(uint256 _newUnaccountedGas) external payable;
}
