// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.26;

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


contract TestTokenPaymaster is TestBase {
    BiconomyTokenPaymaster public tokenPaymaster;
    MockOracle public nativeOracle;
    MockToken public testToken;
    MockToken public testToken2;
    MockOracle public tokenOracle;

    function setUp() public {
        setupPaymasterTestEnvironment();

        // Deploy mock oracles and tokens
        nativeOracle = new MockOracle(100_000_000, 8); // Oracle with 8 decimals for ETH
        tokenOracle = new MockOracle(100_000_000, 8); // Oracle with 8 decimals for ERC20 token
        testToken = new MockToken("Test Token", "TKN");
        testToken2 = new MockToken("Test Token 2", "TKN2");


        // Deploy the token paymaster
        tokenPaymaster = new BiconomyTokenPaymaster(
            PAYMASTER_OWNER.addr,
            PAYMASTER_SIGNER.addr,
            ENTRYPOINT,
            5000, // unaccounted gas
            1e6, // dynamic adjustment
            nativeOracle,
            1 days, // price expiry duration
            _toSingletonArray(address(testToken)),
            _toSingletonArray(IOracle(address(tokenOracle)))
        );
    }

    function test_Deploy() external {
        BiconomyTokenPaymaster testArtifact = new BiconomyTokenPaymaster(
            PAYMASTER_OWNER.addr,
            PAYMASTER_SIGNER.addr,
            ENTRYPOINT,
            5000,
            1e6,
            nativeOracle,
            1 days,
            _toSingletonArray(address(testToken)),
            _toSingletonArray(IOracle(address(tokenOracle)))
        );

        assertEq(testArtifact.owner(), PAYMASTER_OWNER.addr);
        assertEq(address(testArtifact.entryPoint()), ENTRYPOINT_ADDRESS);
        assertEq(testArtifact.verifyingSigner(), PAYMASTER_SIGNER.addr);
        assertEq(address(testArtifact.nativeOracle()), address(nativeOracle));
        assertEq(testArtifact.unaccountedGas(), 5000);
        assertEq(testArtifact.dynamicAdjustment(), 1e6);
    }

    function test_RevertIf_DeployWithSignerSetToZero() external {
        vm.expectRevert(BiconomyTokenPaymasterErrors.VerifyingSignerCanNotBeZero.selector);
        new BiconomyTokenPaymaster(
            PAYMASTER_OWNER.addr,
            address(0),
            ENTRYPOINT,
            5000,
            1e6,
            nativeOracle,
            1 days,
            _toSingletonArray(address(testToken)),
            _toSingletonArray(IOracle(address(tokenOracle)))
        );
    }

    function test_RevertIf_DeployWithSignerAsContract() external {
        vm.expectRevert(BiconomyTokenPaymasterErrors.VerifyingSignerCanNotBeContract.selector);
        new BiconomyTokenPaymaster(
            PAYMASTER_OWNER.addr,
            address(ENTRYPOINT),
            ENTRYPOINT,
            5000,
            1e6,
            nativeOracle,
            1 days,
            _toSingletonArray(address(testToken)),
            _toSingletonArray(IOracle(address(tokenOracle)))
        );
    }

    function test_RevertIf_UnaccountedGasTooHigh() external {
        vm.expectRevert(BiconomyTokenPaymasterErrors.UnaccountedGasTooHigh.selector);
        new BiconomyTokenPaymaster(
            PAYMASTER_OWNER.addr,
            PAYMASTER_SIGNER.addr,
            ENTRYPOINT,
            50_001, // too high unaccounted gas
            1e6,
            nativeOracle,
            1 days,
            _toSingletonArray(address(testToken)),
            _toSingletonArray(IOracle(address(tokenOracle)))
        );
    }

    function test_RevertIf_InvalidDynamicAdjustment() external {
        vm.expectRevert(BiconomyTokenPaymasterErrors.InvalidDynamicAdjustment.selector);
        new BiconomyTokenPaymaster(
            PAYMASTER_OWNER.addr,
            PAYMASTER_SIGNER.addr,
            ENTRYPOINT,
            5000,
            2e6 + 1, // too high dynamic adjustment
            nativeOracle,
            1 days,
            _toSingletonArray(address(testToken)),
            _toSingletonArray(IOracle(address(tokenOracle)))
        );
    }

    function test_SetVerifyingSigner() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectEmit(true, true, true, true, address(tokenPaymaster));
        emit IBiconomyTokenPaymaster.UpdatedVerifyingSigner(PAYMASTER_SIGNER.addr, BOB_ADDRESS, PAYMASTER_OWNER.addr);
        tokenPaymaster.setSigner(BOB_ADDRESS);
        assertEq(tokenPaymaster.verifyingSigner(), BOB_ADDRESS);
    }

    function test_RevertIf_SetVerifyingSignerToZero() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectRevert(BiconomyTokenPaymasterErrors.VerifyingSignerCanNotBeZero.selector);
        tokenPaymaster.setSigner(address(0));
    }

    function test_SetFeeCollector() external prankModifier(PAYMASTER_OWNER.addr) {
        // Set the expected fee collector change and expect the event to be emitted
        vm.expectEmit(true, true, true, true, address(tokenPaymaster));
        emit IBiconomyTokenPaymaster.UpdatedFeeCollector(address(tokenPaymaster), BOB_ADDRESS, PAYMASTER_OWNER.addr);

        // Call the function to set the fee collector
        tokenPaymaster.setFeeCollector(BOB_ADDRESS);

        // Assert the change has been applied correctly
        assertEq(tokenPaymaster.feeCollector(), BOB_ADDRESS);
    }

    function test_Deposit() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 depositAmount = 10 ether;
        assertEq(tokenPaymaster.getDeposit(), 0);

        tokenPaymaster.deposit{ value: depositAmount }();
        assertEq(tokenPaymaster.getDeposit(), depositAmount);
    }

    function test_WithdrawTo() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 depositAmount = 10 ether;
        tokenPaymaster.deposit{ value: depositAmount }();
        uint256 initialBalance = BOB_ADDRESS.balance;

        // Withdraw ETH to BOB_ADDRESS and verify the balance changes
        tokenPaymaster.withdrawTo(payable(BOB_ADDRESS), depositAmount);

        assertEq(BOB_ADDRESS.balance, initialBalance + depositAmount);
        assertEq(tokenPaymaster.getDeposit(), 0);
    }

    function test_WithdrawERC20() external prankModifier(PAYMASTER_OWNER.addr) {
        uint256 mintAmount = 10 * (10 ** testToken.decimals());
        testToken.mint(address(tokenPaymaster), mintAmount);

        // Ensure that the paymaster has the tokens
        assertEq(testToken.balanceOf(address(tokenPaymaster)), mintAmount);
        assertEq(testToken.balanceOf(ALICE_ADDRESS), 0);

        // Expect the `TokensWithdrawn` event to be emitted with the correct values
        vm.expectEmit(true, true, true, true, address(tokenPaymaster));
        emit IBiconomyTokenPaymaster.TokensWithdrawn(
            address(testToken), ALICE_ADDRESS, mintAmount, PAYMASTER_OWNER.addr
        );

        // Withdraw tokens and validate balances
        tokenPaymaster.withdrawERC20(testToken, ALICE_ADDRESS, mintAmount);

        assertEq(testToken.balanceOf(address(tokenPaymaster)), 0);
        assertEq(testToken.balanceOf(ALICE_ADDRESS), mintAmount);
    }

    function test_RevertIf_InvalidOracleDecimals() external {
        MockOracle invalidOracle = new MockOracle(100_000_000, 18); // invalid oracle with 18 decimals
        vm.expectRevert(BiconomyTokenPaymasterErrors.InvalidOracleDecimals.selector);
        new BiconomyTokenPaymaster(
            PAYMASTER_OWNER.addr,
            PAYMASTER_SIGNER.addr,
            ENTRYPOINT,
            5000,
            1e6,
            invalidOracle, // incorrect oracle decimals
            1 days,
            _toSingletonArray(address(testToken)),
            _toSingletonArray(IOracle(address(tokenOracle)))
        );
    }

    function test_SetNativeOracle() external prankModifier(PAYMASTER_OWNER.addr) {
        MockOracle newOracle = new MockOracle(100_000_000, 8);

        vm.expectEmit(true, true, false, true, address(tokenPaymaster));
        emit IBiconomyTokenPaymaster.UpdatedNativeAssetOracle(nativeOracle, newOracle);
        tokenPaymaster.setNativeOracle(newOracle);

        assertEq(address(tokenPaymaster.nativeOracle()), address(newOracle));
    }

    function test_ValidatePaymasterUserOp_ExternalMode() external {
        tokenPaymaster.deposit{ value: 10 ether }();
        testToken.mint(address(ALICE_ACCOUNT), 100_000 * (10 ** testToken.decimals()));
        vm.startPrank(address(ALICE_ACCOUNT));
        testToken.approve(address(tokenPaymaster), testToken.balanceOf(address(ALICE_ACCOUNT)));
        vm.stopPrank();

        // Build the user operation for external mode
        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));
        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);
        uint128 tokenPrice = 1e8; // Assume 1 token = 1 USD
        uint32 externalDynamicAdjustment = 1e6;

        // Generate and sign the token paymaster data
        (bytes memory paymasterAndData,) = generateAndSignTokenPaymasterData(
            userOp,
            PAYMASTER_SIGNER,
            tokenPaymaster,
            3e6, // assumed gas limit for test
            3e6, // assumed verification gas for test
            IBiconomyTokenPaymaster.PaymasterMode.EXTERNAL,
            validUntil,
            validAfter,
            address(testToken),
            tokenPrice,
            externalDynamicAdjustment
        );

        userOp.paymasterAndData = paymasterAndData;
        userOp.signature = signUserOp(ALICE, userOp);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        vm.expectEmit(true, true, false, false, address(tokenPaymaster));
        emit IBiconomyTokenPaymaster.TokensRefunded(address(ALICE_ACCOUNT), address(testToken), 0, bytes32(0));

        vm.expectEmit(true, true, false, false, address(tokenPaymaster));
        emit IBiconomyTokenPaymaster.PaidGasInTokens(address(ALICE_ACCOUNT), address(testToken), 0, 0, 1e6, bytes32(0));

        // Execute the operation
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
    }

    function test_ValidatePaymasterUserOp_IndependentMode() external {
        tokenPaymaster.deposit{ value: 10 ether }();
        testToken.mint(address(ALICE_ACCOUNT), 100_000 * (10 ** testToken.decimals()));
        vm.startPrank(address(ALICE_ACCOUNT));
        testToken.approve(address(tokenPaymaster), testToken.balanceOf(address(ALICE_ACCOUNT)));
        vm.stopPrank();

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));

        // Encode paymasterAndData for independent mode
        bytes memory paymasterAndData = abi.encodePacked(
            address(tokenPaymaster),
            uint128(3e6), // assumed gas limit for test
            uint128(3e6), // assumed verification gas for test
            uint8(IBiconomyTokenPaymaster.PaymasterMode.INDEPENDENT),
            address(testToken)
        );

        userOp.paymasterAndData = paymasterAndData;
        userOp.signature = signUserOp(ALICE, userOp);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        vm.expectEmit(true, true, false, false, address(tokenPaymaster));
        emit IBiconomyTokenPaymaster.TokensRefunded(address(ALICE_ACCOUNT), address(testToken), 0, bytes32(0));

        vm.expectEmit(true, true, false, false, address(tokenPaymaster));
        emit IBiconomyTokenPaymaster.PaidGasInTokens(address(ALICE_ACCOUNT), address(testToken), 0, 0, 1e6, bytes32(0));

        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
    }

    // Test multiple ERC20 token withdrawals
    function test_WithdrawMultipleERC20Tokens() external prankModifier(PAYMASTER_OWNER.addr) {
        // Mint tokens to paymaster
        testToken.mint(address(tokenPaymaster), 1000 * (10 ** testToken.decimals()));
        testToken2.mint(address(tokenPaymaster), 2000 * (10 ** testToken2.decimals()));

        assertEq(testToken.balanceOf(address(tokenPaymaster)), 1000 * (10 ** testToken.decimals()));
        assertEq(testToken2.balanceOf(address(tokenPaymaster)), 2000 * (10 ** testToken2.decimals()));

        // Withdraw both tokens
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(testToken);
        tokens[1] = IERC20(testToken2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 500 * (10 ** testToken.decimals());
        amounts[1] = 1000 * (10 ** testToken2.decimals());

        vm.expectEmit(true, true, true, true, address(tokenPaymaster));
        emit IBiconomyTokenPaymaster.TokensWithdrawn(
            address(testToken), ALICE_ADDRESS, amounts[0], PAYMASTER_OWNER.addr
        );

        vm.expectEmit(true, true, true, true, address(tokenPaymaster));
        emit IBiconomyTokenPaymaster.TokensWithdrawn(
            address(testToken2), ALICE_ADDRESS, amounts[1], PAYMASTER_OWNER.addr
        );

        tokenPaymaster.withdrawMultipleERC20(tokens, ALICE_ADDRESS, amounts);

        assertEq(testToken.balanceOf(address(ALICE_ADDRESS)), amounts[0]);
        assertEq(testToken2.balanceOf(address(ALICE_ADDRESS)), amounts[1]);
    }

    // Test scenario where the token price has expired
    function test_RevertIf_PriceExpired() external {
        // Set price expiry duration to a short time for testing
        vm.warp(block.timestamp + 2 days); // Move forward in time to simulate price expiry

        testToken.mint(address(ALICE_ACCOUNT), 100_000 * (10 ** testToken.decimals()));
        vm.startPrank(address(ALICE_ACCOUNT));
        testToken.approve(address(tokenPaymaster), testToken.balanceOf(address(ALICE_ACCOUNT)));
        vm.stopPrank();

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));
        uint128 tokenPrice = 1e8; // Assume 1 token = 1 USD

        (bytes memory paymasterAndData,) = generateAndSignTokenPaymasterData(
            userOp,
            PAYMASTER_SIGNER,
            tokenPaymaster,
            3e6,
            3e6,
            IBiconomyTokenPaymaster.PaymasterMode.INDEPENDENT,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp),
            address(testToken),
            tokenPrice,
            1e6
        );

        userOp.paymasterAndData = paymasterAndData;
        userOp.signature = signUserOp(ALICE, userOp);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        vm.expectRevert();
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
    }

    // Test setting a high dynamic adjustment
    function test_SetDynamicAdjustmentTooHigh() external prankModifier(PAYMASTER_OWNER.addr) {
        vm.expectRevert(BiconomyTokenPaymasterErrors.InvalidDynamicAdjustment.selector);
        tokenPaymaster.setDynamicAdjustment(2e6 + 1); // Setting too high
    }

    // Test invalid signature in external mode
    function test_RevertIf_InvalidSignature_ExternalMode() external {
        tokenPaymaster.deposit{ value: 10 ether }();
        testToken.mint(address(ALICE_ACCOUNT), 100_000 * (10 ** testToken.decimals()));
        vm.startPrank(address(ALICE_ACCOUNT));
        testToken.approve(address(tokenPaymaster), testToken.balanceOf(address(ALICE_ACCOUNT)));
        vm.stopPrank();

        PackedUserOperation memory userOp = buildUserOpWithCalldata(ALICE, "", address(VALIDATOR_MODULE));
        uint128 tokenPrice = 1e8;

        // Create a valid paymasterAndData
        (bytes memory paymasterAndData,) = generateAndSignTokenPaymasterData(
            userOp,
            PAYMASTER_SIGNER,
            tokenPaymaster,
            3e6,
            3e6,
            IBiconomyTokenPaymaster.PaymasterMode.EXTERNAL,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp),
            address(testToken),
            tokenPrice,
            1e6
        );

        // Tamper the signature by altering the last byte
        paymasterAndData[paymasterAndData.length - 1] = bytes1(uint8(paymasterAndData[paymasterAndData.length - 1]) + 1);
        userOp.paymasterAndData = paymasterAndData;

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        vm.expectRevert();
        ENTRYPOINT.handleOps(ops, payable(BUNDLER.addr));
    }

}
