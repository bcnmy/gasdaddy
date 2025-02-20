// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IOracle} from "contracts/interfaces/oracles/IOracle.sol";

struct Price {
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint publishTime;
    }

interface IPythFeed {
    function getPriceUnsafe(bytes32 id) external view returns (Price memory price);
}

contract PythFeedAdapter is IOracle {
    IPythFeed public immutable pythFeed;
    bytes32 public immutable priceId;

    string public name;

    int32 private constant EXPO = -8;

    error InvalidPythFeedAddress();
    error InvalidPythFeedPrecision();
    
    constructor(address pythFeedAddress, string memory _name, bytes32 _priceId) {
        if (pythFeedAddress == address(0)) revert InvalidPythFeedAddress();
        pythFeed = IPythFeed(pythFeedAddress);
        if (pythFeed.getPriceUnsafe(_priceId).expo != EXPO) revert InvalidPythFeedPrecision();
        priceId = _priceId;
        name = _name;
    }

    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        Price memory price = pythFeed.getPriceUnsafe(priceId);
        roundId = 0;
        answer = price.price;
        startedAt = price.publishTime;
        updatedAt = price.publishTime;
        answeredInRound = 0;
    }

    function decimals() external pure returns (uint8) {
        return uint8(uint32(-EXPO));
    }

    function latestAnswer() external view returns (int256) {
        Price memory price = pythFeed.getPriceUnsafe(priceId);
        return price.price;
    }
}

contract DeployPythFeedAdapter is Script {
    function run() public {
        console.log("Deploying PythFeedAdapter");
        vm.startBroadcast();
        //Blast
        //PythFeedAdapter pythFeedAdapter = new PythFeedAdapter(0xA2aa501b19aff244D90cc15a4Cf739D2725B5729, "ETH/USD", 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace);
        //IOTA
        //PythFeedAdapter pythFeedAdapter = new PythFeedAdapter(0x8D254a21b3C86D32F7179855531CE99164721933, "IOTA/USD", 0xc7b72e5d860034288c9335d4d325da4272fe50c92ab72249d58f6cbba30e4c44);
        // SONIC
        PythFeedAdapter pythFeedAdapter = new PythFeedAdapter(0x2880aB155794e7179c9eE2e38200202908C17B43, "S/USD", 0xf490b178d0c85683b7a0f2388b40af2e6f7c90cbe0f96b31f315f08d0e5a2d6d);
        vm.stopBroadcast();
        console.log("PythFeedAdapter deployed at", address(pythFeedAdapter));
    }
}