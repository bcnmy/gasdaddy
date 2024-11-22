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
    // base addresses
    IOracle public nativeOracle = IOracle(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70); // base ETH/USD chainlink feed
    IOracle public tokenOracle = IOracle(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B); // base USDC/USD chainlink feed
    IERC20 public usdc = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913); // base USDC


    function setUp() public {
        uint256 forkId = vm.createFork("https://developer-access-mainnet.base.org");
        vm.selectFork(forkId);

        // Set block to latest block
        // vm.rollFork(21744650);
        // assertEq(block.number, 21744650);
        setupPaymasterTestEnvironment();

        console2.log("current block timestamp ", block.timestamp);

        swapRouter = ISwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481); // uniswap swap router v2 on base
        // Deploy the token paymaster
        tokenPaymaster = new BiconomyTokenPaymaster(
            PAYMASTER_OWNER.addr,
            PAYMASTER_SIGNER.addr,
            ENTRYPOINT,
            50000, // unaccounted gas
            1e6, // price markup (for independent mode)
            1 days, // price expiry duration
            1e18, // native token decimals
            nativeOracle,
            swapRouter,
            WRAPPED_NATIVE_ADDRESS,
            _toSingletonArray(address(usdc)),
            _toSingletonArray(IOracle(address(tokenOracle))),
            _toSingletonArray(address(usdc)),
            _toSingletonArray(uint24(500)) // from here: https://basescan.org/address/0xd0b53D9277642d899DF5C87A3966A349A798F224#readContract
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
            1e18, // native token decimals
            nativeOracle,
            swapRouter,
            WRAPPED_NATIVE_ADDRESS,
            _toSingletonArray(address(usdc)),
            _toSingletonArray(IOracle(address(tokenOracle))),
            _toSingletonArray(address(usdc)),
            _toSingletonArray(uint24(500)) // from here: https://basescan.org/address/0xd0b53D9277642d899DF5C87A3966A349A798F224#readContract
        );

        assertEq(testArtifact.owner(), PAYMASTER_OWNER.addr);
        assertEq(address(testArtifact.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(testArtifact.verifyingSigner(), PAYMASTER_SIGNER.addr);
        assertEq(address(testArtifact.nativeAssetToUsdOracle()), address(nativeOracle));
        assertEq(testArtifact.unaccountedGas(), 50000);
        assertEq(testArtifact.independentPriceMarkup(), 1e6);
    }

    function test_BaseFork_Success_TokenPaymaster_IndependentMode_WithoutPremium() external {
        tokenPaymaster.deposit{ value: 10 ether }();
        deal(address(usdc), address(ALICE_ACCOUNT), 100e6);
        vm.startPrank(address(ALICE_ACCOUNT));
        usdc.approve(address(tokenPaymaster), usdc.balanceOf(address(ALICE_ACCOUNT)));
        vm.stopPrank();

        vm.startPrank(PAYMASTER_OWNER.addr);
        tokenPaymaster.setUnaccountedGas(40_000);
        vm.stopPrank();

        uint256 initialBundlerBalance = BUNDLER.addr.balance;
        uint256 initialPaymasterEpBalance = tokenPaymaster.getDeposit();
        uint256 initialUserTokenBalance = usdc.balanceOf(address(ALICE_ACCOUNT));
        uint256 initialPaymasterTokenBalance = usdc.balanceOf(address(tokenPaymaster));

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));

        // Encode paymasterAndData for independent mode
        bytes memory paymasterAndData = abi.encodePacked(
            address(tokenPaymaster),
            uint128(3e6), // assumed gas limit for test
            uint128(3e6), // assumed verification gas for test
            uint8(IBiconomyTokenPaymaster.PaymasterMode.INDEPENDENT),
            address(usdc)
        );

        userOp.paymasterAndData = paymasterAndData;
        userOp.signature = signUserOp(ALICE, userOp);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        vm.expectEmit(true, true, false, false, address(tokenPaymaster));
        emit IBiconomyTokenPaymaster.TokensRefunded(address(ALICE_ACCOUNT), address(usdc), 0, bytes32(0));

        vm.expectEmit(true, true, false, false, address(tokenPaymaster));
        emit IBiconomyTokenPaymaster.PaidGasInTokens(address(ALICE_ACCOUNT), address(usdc), 0, 0, 1e6, 0, bytes32(0));

        uint256 customGasPrice = 3e6;
        startPrank(BUNDLER.addr);
        vm.txGasPrice(customGasPrice);
        uint256 gasValue = gasleft();   
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
        gasValue = gasValue - gasleft();
        stopPrank();

        calculateAndAssertAdjustmentsForTokenPaymaster(
            tokenPaymaster,
            usdc, 
            initialBundlerBalance, 
            initialPaymasterEpBalance, 
            initialUserTokenBalance, 
            initialPaymasterTokenBalance,
            // IF THIS CASE FAILS ON 2% TOLERANCE => PUT THE FRESH PRICE FROM ORACLE HERE
            3344583445,
            _PRICE_MARKUP_DENOMINATOR,
            this.getMaxPenalty(ops[0]),
            this.getRealPenalty(ops[0], gasValue, customGasPrice));
    }

    // test to make a swap.
    function test_BaseFork_Success_TokenPaymaster_SwapToNativeAndDeposit() external {
       deal(address(usdc), address(tokenPaymaster), 100e6);
       uint256 initialTokenBalance = usdc.balanceOf(address(tokenPaymaster));
       console2.log("initialTokenBalance", initialTokenBalance);
       uint256 initialDepositOnEntryPoint = tokenPaymaster.getDeposit();

    //    vm.startPrank(address(tokenPaymaster));
    //    usdc.approve(address(SWAP_ROUTER_ADDRESS), usdc.balanceOf(address(tokenPaymaster)));
    //    vm.stopPrank();

       // Review reason for failure
       startPrank(PAYMASTER_OWNER.addr);
       tokenPaymaster.swapTokenAndDeposit(address(usdc), 1e6, 0);
       stopPrank();

       // uint256 newTokenBalance = usdc.balanceOf(address(tokenPaymaster));
       // assertEq(newTokenBalance, 0);

       // uint256 newDepositOnEntryPoint = tokenPaymaster.getDeposit();
       // assertGt(newDepositOnEntryPoint, initialDepositOnEntryPoint);
    }
}

