// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.27;

contract BiconomySponsorshipPaymasterErrors {
    /**
     * @notice Throws when the paymaster address provided is address(0)
     */
    error PaymasterIdCanNotBeZero();

    /**
     * @notice Throws when the 0 has been provided as deposit
     */
    error DepositCanNotBeZero();

    /**
     * @notice Throws when the verifiying signer address provided is address(0)
     */
    error VerifyingSignerCanNotBeZero();

    /**
     * @notice Throws when the fee collector address provided is address(0)
     */
    error FeeCollectorCanNotBeZero();

    /**
     * @notice Throws when the fee collector address provided is a deployed contract
     */
    error FeeCollectorCanNotBeContract();

    /**
     * @notice Throws when the fee collector address provided is a deployed contract
     */
    error VerifyingSignerCanNotBeContract();

    /**
     * @notice Throws when ETH withdrawal fails
     */
    error WithdrawalFailed();

    /**
     * @notice Throws when insufficient funds to withdraw
     */
    error InsufficientFunds();

    /**
     * @notice Throws when invalid signature length in paymasterAndData
     */
    error InvalidSignatureLength();

    /**
     * @notice Throws when invalid signature length in paymasterAndData
     */
    error InvalidPriceMarkup();

    /**
     * @notice Throws when insufficient funds for paymasterid
     */
    error InsufficientFundsForPaymasterId();

    /**
     * @notice Throws when calling deposit()
     */
    error UseDepositForInstead();

    /**
     * @notice Throws when trying to withdraw to address(0)
     */
    error CanNotWithdrawToZeroAddress();

    /**
     * @notice Throws when trying to withdraw zero amount
     */
    error CanNotWithdrawZeroAmount();

    /**
     * @notice Throws when trying unaccountedGas is too high
     */
    error UnaccountedGasTooHigh();
}
