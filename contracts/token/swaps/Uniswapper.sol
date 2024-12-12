// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryPayments.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

/**
 * @title Uniswapper
 * @author ShivaanshK<shivaansh.kapoor@biconomy.io>
 * @notice An abstract contract to assist the paymaster in swapping tokens to WETH and unwrapping WETH
 * @notice Based on Infinitism's Uniswap Helper contract
 */
abstract contract Uniswapper {

    event SwappingReverted(address tokenIn, uint256 amountIn, bytes reason);
    error UnwrappingReverted(uint256 amount);

    /// @notice The ERC-20 token that wraps the native asset for current chain
    address public immutable wrappedNative;

    // Token address -> Fee tier of the pool to swap through
    mapping(address => uint24) public tokenToPools;

    /// @notice The Uniswap V3 SwapRouter contract
    IV3SwapRouter public uniswapRouter;

    // Errors
    error UniswapReverted(address tokenIn, address tokenOut, uint256 amountIn);
    error TokensAndPoolsLengthMismatch();
    error TokenNotSupported();

    constructor(
        IV3SwapRouter uniswapRouterArg,
        address wrappedNativeArg,
        address[] memory tokens,
        uint24[] memory tokenPoolFeeTiers
    ) {
        if (tokens.length != tokenPoolFeeTiers.length) {
            revert TokensAndPoolsLengthMismatch();
        }

        // Set router and native wrapped asset addresses
        uniswapRouter = uniswapRouterArg;
        wrappedNative = wrappedNativeArg;

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).approve(address(uniswapRouter), type(uint256).max); // one time max approval
            tokenToPools[tokens[i]] = tokenPoolFeeTiers[i]; // set mapping of token to uniswap pool to use for swap
        }
    }

    function _setTokenPool(address token, uint24 poolFeeTier) internal {
        SafeERC20.forceApprove(IERC20(token), address(uniswapRouter), type(uint256).max); // one time max approval
        tokenToPools[token] = poolFeeTier; // set mapping of token to uniswap pool to use for swap
    }

    function _swapTokenToWeth(address tokenIn, uint256 amountIn, uint256 minAmountOut) internal returns (uint256 amountOut) {
        require(tokenToPools[tokenIn] != 0, TokenNotSupported());
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: wrappedNative,
            fee: tokenToPools[tokenIn],
            recipient: address(this),
            //deadline: block.timestamp, // legacy interface arg. Intentiaonally omitted.
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        try uniswapRouter.exactInputSingle(params) returns (uint256 _amountOut) {
            amountOut = _amountOut;
        } catch (bytes memory reason) {
            emit SwappingReverted(tokenIn, amountIn, reason);
            amountOut = 0;
        }
    }

    function _unwrapWeth(uint256 amount) internal {
        if(amount == 0) return;
        (bool success, ) = address(wrappedNative).call(abi.encodeWithSignature("withdraw(uint256)", amount));
        if (!success) revert UnwrappingReverted(amount);
    }

    function _setUniswapRouter(IV3SwapRouter uniswapRouterArg) internal {
        uniswapRouter = uniswapRouterArg;
    }
}
