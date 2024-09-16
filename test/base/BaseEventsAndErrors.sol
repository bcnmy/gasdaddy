// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.26;

import { EventsAndErrors } from "@nexus/test/foundry/utils/EventsAndErrors.sol";
import { BiconomySponsorshipPaymasterErrors } from "../../contracts/common/BiconomySponsorshipPaymasterErrors.sol";

contract BaseEventsAndErrors is EventsAndErrors, BiconomySponsorshipPaymasterErrors {
    // ==========================
    // Events
    // ==========================
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    // ==========================
    // Errors
    // ==========================
    error NewOwnerIsZeroAddress();
}
