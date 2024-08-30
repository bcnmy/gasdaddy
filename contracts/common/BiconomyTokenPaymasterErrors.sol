// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.26;

contract BiconomyTokenPaymasterErrors {
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
    error VerifyingSignerCanNotBeContract();

    /**
     * @notice Throws when trying unaccountedGas is too high
     */
    error UnaccountedGasTooHigh();

    /**
     * @notice Throws when trying to withdraw to address(0)
     */
    error CanNotWithdrawToZeroAddress();

    /**
     * @notice Throws when trying to withdraw multiple tokens, but each token doesn't have a corresponding amount
     */
    error TokensAndAmountsLengthMismatch();
}
