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

}