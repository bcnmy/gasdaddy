// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;
pragma solidity >=0.8.0 <0.9.0;


import { BaseScript } from "./Base.s.sol";
import {
    BiconomyTokenPaymaster,
    IBiconomyTokenPaymaster,
    BiconomyTokenPaymasterErrors,
    IOracle
} from "../../../contracts/token/BiconomyTokenPaymaster.sol";
import { MockOracle } from "../../test/mocks/MockOracle.sol";
import { MockToken } from "@nexus/contracts/mocks/MockToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../../contracts/token/swaps/Uniswapper.sol";
import { IEntryPoint } from "account-abstraction/interfaces/IEntryPoint.sol";

import "forge-std/console2.sol";

contract DeployTokenPMTest is BaseScript {

    BiconomyTokenPaymaster public tokenPaymaster;
    ISwapRouter swapRouter;
    MockOracle public nativeAssetToUsdOracle;
    MockToken public testToken;
    MockToken public testToken2;
    MockOracle public tokenOracle;

    address private constant ENTRYPOINT_MAINNET_ADDRESS = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    address private constant WRAPPED_NATIVE_ADDRESS = 0x4200000000000000000000000000000000000006;
    address private constant SWAP_ROUTER_ADDRESS = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address private constant PAYMASTER_OWNER = 0x531b827c1221EC7CE13266e8F5CB1ec6Ae470be5;
    address private constant PAYMASTER_SIGNER = 0x531b827c1221EC7CE13266e8F5CB1ec6Ae470be5;

    function run() public broadcast returns (address) {
        require(address(ENTRYPOINT_MAINNET_ADDRESS) != address(0), "ENTRYPOINT is not set");

        // Deploy mock oracles and tokens
        swapRouter = ISwapRouter(address(SWAP_ROUTER_ADDRESS));
        nativeAssetToUsdOracle = new MockOracle(100_000_000, 8); // Oracle with 8 decimals for ETH // ETH/USD
        tokenOracle = new MockOracle(100_000_000, 8); // Oracle with 8 decimals for ERC20 token // TKN/USD
        testToken = new MockToken("Test Token", "TKN");
        testToken2 = new MockToken("Test Token 2", "TKN2");

        // Deploy the token paymaster
        tokenPaymaster = new BiconomyTokenPaymaster(
            PAYMASTER_OWNER,
            PAYMASTER_SIGNER,
            IEntryPoint(ENTRYPOINT_MAINNET_ADDRESS),
            50000, // unaccounted gas
            1e6, // price markup
            1 days, // price expiry duration
            1e18, // native token decimals
            nativeAssetToUsdOracle,
            swapRouter,
            WRAPPED_NATIVE_ADDRESS,
            _toSingletonArray(address(testToken)),
            _toSingletonArray(IOracle(address(tokenOracle))),
            new address[](0),
            new uint24[](0)
        );

        tokenPaymaster.deposit{ value: 0.05 ether }();

        console2.log("Token Paymaster deployed at:", address(tokenPaymaster));

        return address(tokenPaymaster);
    }

    function _toSingletonArray(address addr) internal pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = addr;
        return array;
    }

    function _toSingletonArray(uint24 element) internal pure returns (uint24[] memory) {
    uint24[] memory array = new uint24[](1);
    array[0] = element;
        return array;
    }

    function _toSingletonArray(IOracle oracle) internal pure returns (IOracle[] memory) {
        IOracle[] memory array = new IOracle[](1);
        array[0] = oracle;
        return array;
    }
}