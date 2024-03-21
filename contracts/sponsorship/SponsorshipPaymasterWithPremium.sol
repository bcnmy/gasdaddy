// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/* solhint-disable reason-string */

import "../base/BasePaymaster.sol";
import "account-abstraction/contracts/core/UserOperationLib.sol";
import "account-abstraction/contracts/core/Helpers.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { SignatureCheckerLib } from "solady/src/utils/SignatureCheckerLib.sol";
import { ECDSA as ECDSA_solady } from "solady/src/utils/ECDSA.sol";
import { BiconomySponsorshipPaymasterErrors } from "../common/Errors.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IBiconomySponsorshipPaymaster } from "../interfaces/IBiconomySponsorshipPaymaster.sol";

// possiblity (conflicts with BasePaymaster which is also Ownbale) // either make BasePaymaster SoladyOwnable
// import { SoladyOwnable } from "../utils/SoladyOwnable.sol";

/**
 * @title BiconomySponsorshipPaymaster
 * @author livingrockrises<chirag@biconomy.io>
 * @notice Based on Infinitism 'VerifyingPaymaster' contract
 * @dev This contract is used to sponsor the transaction fees of the user operations
 * Uses a verifying signer to provide the signature if predetermined conditions are met 
 * regarding the user operation calldata. Also this paymaster is Singleton in nature which 
 * means multiple Dapps/Wallet clients willing to sponsor the transactions can share this paymaster.
 * Maintains it's own accounting of the gas balance for each Dapp/Wallet client 
 * and Manages it's own deposit on the EntryPoint.
 */

// Todo: Add more methods in interface
// Todo: Add methods to withdraw stuck erc20 tokens and native tokens

abstract contract BiconomySponsorshipPaymaster is BasePaymaster, ReentrancyGuard, BiconomySponsorshipPaymasterErrors, IBiconomySponsorshipPaymaster {
    using UserOperationLib for PackedUserOperation;

    address public verifyingSigner;
    address public feeCollector;
    uint32 private constant PRICE_DENOMINATOR = 1e6;

    // note: could rename to PAYMASTER_ID_OFFSET
    uint256 private constant VALID_PND_OFFSET = PAYMASTER_DATA_OFFSET;

    // temp
    // paymasterAndData: paymaster address + paymaster gas limits + paymasterData
    // paymasterData: concat of [paymasterId(20 bytes), validUntil(6 bytes), validAfter(6 bytes), priceMarkup(4 bytes), signature]

    mapping(address => uint256) public paymasterIdBalances;

    constructor(address _owner, IEntryPoint _entryPoint, address _verifyingSigner, address _feeCollector) BasePaymaster(_entryPoint) {
        // TODO
        // Check for zero address
        verifyingSigner = _verifyingSigner;
        feeCollector = _feeCollector;
        _transferOwnership(_owner);
    }

    /**
     * @dev Add a deposit for this paymaster and given paymasterId (Dapp Depositor address), used for paying for transaction fees
     * @param paymasterId dapp identifier for which deposit is being made
     */
    function depositFor(address paymasterId) external payable nonReentrant {
        if (paymasterId == address(0)) revert PaymasterIdCannotBeZero();
        if (msg.value == 0) revert DepositCanNotBeZero();
        paymasterIdBalances[paymasterId] += msg.value;
        entryPoint.depositTo{value: msg.value}(address(this));
        emit GasDeposited(paymasterId, msg.value);
    }

}