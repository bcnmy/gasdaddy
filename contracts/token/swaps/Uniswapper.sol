// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

/* solhint-disable not-rely-on-time */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryPayments.sol";

abstract contract Uniswapper {
    uint256 private constant SWAP_PRICE_DENOMINATOR = 1e26;

    /// @notice The Uniswap V3 SwapRouter contract
    ISwapRouter public immutable uniswapRouter;

    /// @notice The ERC-20 token that wraps the native asset for current chain
    address public immutable wrappedNative;

    // Token address -> Fee tier of the pool to swap through
    mapping(address => uint24) public tokenToPools;

    event UniswapReverted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn);

    error TokensAndAmountsLengthMismatch();

    constructor(
        ISwapRouter _uniswapRouter,
        address _wrappedNative,
        address[] memory _tokens,
        uint24[] memory _tokenPools
    ) {
        if (_tokens.length != _tokenPools.length) {
            revert TokensAndAmountsLengthMismatch();
        }

        // Set router and native wrapped asset addresses
        uniswapRouter = _uniswapRouter;
        wrappedNative = _wrappedNative;

        for (uint256 i = 0; i < _tokens.length; ++i) {
            IERC20(_tokens[i]).approve(address(_uniswapRouter), type(uint256).max); // one time max approval
            tokenToPools[_tokens[i]] = _tokenPools[i]; // set mapping of token to uniswap pool to use for swap
        }
    }

    function _setTokenPool(address _token, uint24 _feeTier) internal {
        IERC20(_token).approve(address(uniswapRouter), type(uint256).max); // one time max approval
        tokenToPools[_token] = _feeTier; // set mapping of token to uniswap pool to use for swap
    }

    function _swapTokenToWeth(address _tokenIn, uint256 _amountIn) internal returns (uint256 amountOut) {
        uint24 poolFee = tokenToPools[_tokenIn];

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: wrappedNative,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        try uniswapRouter.exactInputSingle(params) returns (uint256 _amountOut) {
            amountOut = _amountOut;
        } catch {
            emit UniswapReverted(_tokenIn, wrappedNative, _amountIn);
            amountOut = 0;
        }
    }

    function addSlippage(uint256 amount, uint8 slippage) private pure returns (uint256) {
        return amount * (1000 - slippage) / 1000;
    }

    function tokenToWei(uint256 amount, uint256 price) public pure returns (uint256) {
        return amount * price / SWAP_PRICE_DENOMINATOR;
    }

    function weiToToken(uint256 amount, uint256 price) public pure returns (uint256) {
        return amount * SWAP_PRICE_DENOMINATOR / price;
    }

    function unwrapWeth(uint256 _amount) internal {
        IPeripheryPayments(address(uniswapRouter)).unwrapWETH9(_amount, address(this));
    }
}
