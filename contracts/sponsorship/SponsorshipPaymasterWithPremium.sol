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