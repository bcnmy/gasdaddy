// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IOracle } from "../../interfaces/oracles/IOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/libraries/OracleLibrary.sol";
import { IUniswapV3PoolImmutables } from "@uniswap/v3-core/interfaces/pool/IUniswapV3PoolImmutables.sol";

contract TwapOracle is IOracle {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev The Uniswap V3 pool address
    address public immutable pool;

    /// @dev The base token address (the one which price is being fetched)
    address public immutable baseToken;

    /// @dev The base token decimals
    uint256 public immutable baseTokenDecimals;

    /// @dev The quote token address (WETH or USD stable coin)
    address public immutable quoteToken;

    /// @dev The quote token decimals
    uint256 public immutable quoteTokenDecimals;

    /// @dev Default TWAP age, used to fetch the price
    uint32 public immutable twapAge;

    uint32 public constant MINIMUM_TWAP_AGE = 1 minutes;
    uint32 public constant MAXIMUM_TWAP_AGE = 7 days;

    uint256 public constant ORACLE_DECIMALS = 1e8;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Invalid TWAP age, either too low or too high
    error InvalidTwapAge();

    /// @dev Pool doesn't contain the base token
    error InvalidTokenOrPool();

    constructor(address poolArg, uint32 twapAgeArg, address baseTokenArg) {
        pool = poolArg;

        if (twapAgeArg < MINIMUM_TWAP_AGE || twapAgeArg > MAXIMUM_TWAP_AGE) revert InvalidTwapAge();
        twapAge = twapAgeArg;

        address token0 = IUniswapV3PoolImmutables(poolArg).token0();
        address token1 = IUniswapV3PoolImmutables(poolArg).token1();

        if (baseTokenArg != token0 && baseTokenArg != token1) revert InvalidTokenOrPool();

        baseToken = baseTokenArg;
        baseTokenDecimals = 10 ** IERC20Metadata(baseTokenArg).decimals();

        quoteToken = token0 == baseToken ? token1 : token0;
        quoteTokenDecimals = 10 ** IERC20Metadata(quoteToken).decimals();
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        uint256 price = _fetchTwap();

        // Normalize the price to the oracle decimals
        uint256 normalizedPrice = (price * ORACLE_DECIMALS) / quoteTokenDecimals;

        return _buildLatestRoundData(normalizedPrice);
    }

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function _buildLatestRoundData(
        uint256 price
    )
        internal
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, int256(price), 0, block.timestamp, 0);
    }

    function _fetchTwap() internal view returns (uint256) {
        (int24 arithmeticMeanTick,) = OracleLibrary.consult(pool, twapAge);

        return OracleLibrary.getQuoteAtTick(
            arithmeticMeanTick,
            uint128(baseTokenDecimals), // Base token amount is equal to 1 token
            baseToken,
            quoteToken
        );
    }
}
