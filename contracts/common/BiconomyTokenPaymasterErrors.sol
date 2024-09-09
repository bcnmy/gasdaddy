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

    /**
     * @notice Throws when invalid signature length in paymasterAndData
     */
    error InvalidDynamicAdjustment();

    /**
     * @notice Throws when each token doesnt have a corresponding oracle
     */
    error TokensAndInfoLengthMismatch();

    /**
     * @notice Throws when oracle returns invalid price
     */
    error OraclePriceNotPositive();

    /**
     * @notice Throws when oracle price hasn't been updated for a duration of time the owner is comfortable with
     */
    error OraclePriceExpired();
}
