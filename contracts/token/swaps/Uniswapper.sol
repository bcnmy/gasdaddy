// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryPayments.sol";

/**
 * @title Uniswapper
 * @author ShivaanshK<shivaansh.kapoor@biconomy.io>
 * @notice An abstract contract to assist the paymaster in swapping tokens to WETH and unwrapping WETH
 * @notice Based on Infinitism's Uniswap Helper contract
 */
abstract contract Uniswapper {
    uint256 private constant SWAP_PRICE_DENOMINATOR = 1e26;

    /// @notice The Uniswap V3 SwapRouter contract
    ISwapRouter public immutable uniswapRouter;

    /// @notice The ERC-20 token that wraps the native asset for current chain
    address public immutable wrappedNative;

    // Token address -> Fee tier of the pool to swap through
    mapping(address => uint24) public tokenToPools;

    // Errors
    error UniswapReverted(address tokenIn, address tokenOut, uint256 amountIn);
    error TokensAndPoolsLengthMismatch();

    constructor(
        ISwapRouter _uniswapRouter,
        address _wrappedNative,
        address[] memory _tokens,
        uint24[] memory _tokenPoolFeeTiers
    ) {
        if (_tokens.length != _tokenPoolFeeTiers.length) {
            revert TokensAndPoolsLengthMismatch();
        }

        // Set router and native wrapped asset addresses
        uniswapRouter = _uniswapRouter;
        wrappedNative = _wrappedNative;

        for (uint256 i = 0; i < _tokens.length; ++i) {
            IERC20(_tokens[i]).approve(address(_uniswapRouter), type(uint256).max); // one time max approval
            tokenToPools[_tokens[i]] = _tokenPoolFeeTiers[i]; // set mapping of token to uniswap pool to use for swap
        }
    }

    function _setTokenPool(address _token, uint24 _poolFeeTier) internal {
        IERC20(_token).approve(address(uniswapRouter), type(uint256).max); // one time max approval
        tokenToPools[_token] = _poolFeeTier; // set mapping of token to uniswap pool to use for swap
    }

    function _swapTokenToWeth(address _tokenIn, uint256 _amountIn, uint256 _minAmountOut) internal returns (uint256) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: wrappedNative,
            fee: tokenToPools[_tokenIn],
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: _minAmountOut,
            sqrtPriceLimitX96: 0
        });
        return uniswapRouter.exactInputSingle(params);
    }

    function _unwrapWeth(uint256 _amount) internal {
        IPeripheryPayments(address(uniswapRouter)).unwrapWETH9(_amount, address(this));
    }
}
