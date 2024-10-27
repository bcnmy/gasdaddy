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

contract TestTokenPaymasterBase is TestBase {
    BiconomyTokenPaymaster public tokenPaymaster;
    ISwapRouter public swapRouter;
    IOracle public nativeOracle = IOracle(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70); // base ETH/USD chainlink feed
    IOracle public tokenOracle = IOracle(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B); // base USDC/USD chainlink feed
    IERC20 public usdc = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913); // base USDC


    function setUp() public {
        uint256 forkId = vm.createFork("https://developer-access-mainnet.base.org");
        vm.selectFork(forkId);
        setupPaymasterTestEnvironment();

        swapRouter = ISwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481); // uniswap swap router v2 on base
        // Deploy the token paymaster
        tokenPaymaster = new BiconomyTokenPaymaster(
            PAYMASTER_OWNER.addr,
            PAYMASTER_SIGNER.addr,
            ENTRYPOINT,
            50000, // unaccounted gas
            1e6, // price markup
            1 days, // price expiry duration
            nativeOracle,
            swapRouter,
            WRAPPED_NATIVE_ADDRESS,
            _toSingletonArray(address(usdc)),
            _toSingletonArray(IOracle(address(tokenOracle))),
            new address[](0),
            new uint24[](0)
        );
    }

    function test_Deploy_BaseFork() external {
        // Deploy the token paymaster
        BiconomyTokenPaymaster testArtifact = new BiconomyTokenPaymaster(
            PAYMASTER_OWNER.addr,
            PAYMASTER_SIGNER.addr,
            ENTRYPOINT,
            50000, // unaccounted gas
            1e6, // price markup
            1 days, // price expiry duration
            nativeOracle,
            swapRouter,
            WRAPPED_NATIVE_ADDRESS,
            _toSingletonArray(address(usdc)),
            _toSingletonArray(IOracle(address(tokenOracle))),
            new address[](0),
            new uint24[](0)
        );

        assertEq(testArtifact.owner(), PAYMASTER_OWNER.addr);
        assertEq(address(testArtifact.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(testArtifact.verifyingSigner(), PAYMASTER_SIGNER.addr);
        assertEq(address(testArtifact.nativeAssetToUsdOracle()), address(nativeOracle));
        assertEq(testArtifact.unaccountedGas(), 50000);
        assertEq(testArtifact.independentPriceMarkup(), 1e6);
    }
}
