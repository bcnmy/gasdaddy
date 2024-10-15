// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "contracts/interfaces/oracles/IOracle.sol";

contract MockOracle is IOracle {
    int256 public price;
    uint8 public priceDecimals;
    uint256 public updatedAtDelay;

    constructor(int256 _initialPrice, uint8 _decimals) {
        price = _initialPrice;
        priceDecimals = _decimals;
        updatedAtDelay = 0;
    }

    /**
     * @dev Allows setting a new price manually for testing purposes.
     * @param _price The new price to be set.
     */
    function setPrice(int256 _price) external {
        price = _price;
    }

    /**
     * @dev Allows setting the delay for the `updatedAt` timestamp.
     * @param _updatedAtDelay The delay in seconds to simulate a stale price.
     */
    function setUpdatedAtDelay(uint256 _updatedAtDelay) external {
        updatedAtDelay = _updatedAtDelay;
    }

    /**
     * @dev Returns the number of decimals for the oracle price feed.
     */
    function decimals() external view override returns (uint8) {
        return priceDecimals;
    }

    /**
     * @dev Mocks a random price within a given range.
     * @param minPrice The minimum price range (inclusive).
     * @param maxPrice The maximum price range (inclusive).
     */
    function setRandomPrice(int256 minPrice, int256 maxPrice) external {
        require(minPrice <= maxPrice, "Min price must be less than or equal to max price");

        // Generate a random price within the range [minPrice, maxPrice]
        price = minPrice
            + int256(
                uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))) % uint256(maxPrice - minPrice + 1)
            );
    }

    /**
     * @dev Returns mocked data for the latest round of the price feed.
     * @return _roundId The round ID.
     * @return answer The current price.
     * @return startedAt The timestamp when the round started.
     * @return _updatedAt The timestamp when the round was last updated.
     * @return answeredInRound The round ID in which the answer was computed.
     */
    function latestRoundData()
        external
        view
        override
        returns (uint80 _roundId, int256 answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound)
    {
        return (
            73_786_976_294_838_215_802, // Mock round ID
            price, // The current price
            block.timestamp, // Simulate round started at the current block timestamp
            block.timestamp - updatedAtDelay, // Simulate price last updated with delay
            73_786_976_294_838_215_802 // Mock round ID for answeredInRound
        );
    }
}
