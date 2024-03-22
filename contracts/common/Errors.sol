// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.24;

contract BiconomySponsorshipPaymasterErrors {

    /**
     * @notice Throws when the paymaster address provided is address(0)
     */
    error PaymasterIdCannotBeZero();

    /**
     * @notice Throws when the 0 has been provided as deposit
     */
    error DepositCanNotBeZero();

    /**
     * @notice Throws when the verifiying signer address provided is address(0)
     */
    error VerifyingSignerCannotBeZero();

    /**
     * @notice Throws when the fee collector address provided is address(0)
     */
    error FeeCollectorCannotBeZero();

    /**
     * @notice Throws when the fee collector address provided is a deployed contract
     */
    error FeeCollectorCannotBeContract();

    /**
     * @notice Throws when the fee collector address provided is a deployed contract
     */
    error VerifyingSignerCannotBeContract();

    /**
     * @notice Throws when trying to withdraw to address(0)
     */
    error CanNotWithdrawToZeroAddress();

}