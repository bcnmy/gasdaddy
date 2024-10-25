// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.27;

import "../../base/TestBase.sol";
import {
    BiconomyTokenPaymaster,
    IBiconomyTokenPaymaster,
    BiconomyTokenPaymasterErrors,
    IOracle
} from "../../../contracts/token/BiconomyTokenPaymaster.sol";
import { MockOracle } from "../../mocks/MockOracle.sol";
import { MockToken } from "@nexus/contracts/mocks/MockToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../../contracts/token/swaps/Uniswapper.sol";

// Todo: work on fork of Base.