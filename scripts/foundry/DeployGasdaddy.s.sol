// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {DeterministicDeployerLib} from "./utils/DeterministicDeployerLib.sol";
import {IBiconomyTokenPaymaster} from "contracts/interfaces/IBiconomyTokenPaymaster.sol";
import {MockOracle} from "test/mocks/MockOracle.sol";
import {WETH9} from "contracts/mocks/WETH9.sol";


interface Create3Deployer {
    function addressOf(bytes32 salt) external view returns (address);

    function deploy(bytes32 salt, bytes calldata creationCode, bytes calldata signature) external returns (address);
}

contract DeployGasdaddy is Script {

    struct TokenPMConfig {
        address nativeAssetToUsdOracle;
        uint256 nativeAssetDecimals;
        uint256 nativeAssetPriceExpiryDuration;
        address wrappedNativeAddress;
        address swapRouter;
        address[] independentTokens;
        IBiconomyTokenPaymaster.TokenInfo[] tokenInfos;
    }

    // SALTS
    bytes32 constant SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT = 0xc9ec6c618ddf6abc86e028d1ec4b5134220e43bf3077b043e67f191f9eb347e1; //  ==> 0x000000f05e956f96bbcbf39012809070da94047c
    bytes32 constant TOKEN_PAYMASTER_DEPLOYMENT_SALT = 0xacde7b202f0f9becc0dc7d3f759f4c7f3aad958d689fc89cba2de30ac6dcb661; // 0x00000000301515a5410e0d768af4f53c416edf19
    // bytes32 constant TOKEN_PAYMASTER_DEPLOYMENT_SALT = 0x38b3bd986a7d84de00ac8e7a738bec546ee9b15bf26e12af54823d252ba868f7; // ==> 0x000000e5c375f0b44015386c338ce5ddf72d600b
    // backup salt 0x724dd9b57a6505c7389fa9ee13b55404929a38dda59f440c5f3bd8c24bf05497 ==> 0x0000008e81b7464dcc67669ea8624ab4486553b3 (not used yet)

    // CONSTRUCTOR ARGS
    address constant VERIFYING_PAYMASTER_OWNER = 0x129443cA2a9Dec2020808a2868b38dDA457eaCC7;
    address constant VERIFYING_SIGNER = 0xC6dAB8652E5E9749523bA948F42d5944584E4e73;
    address constant FEE_COLLECTOR = 0x129443cA2a9Dec2020808a2868b38dDA457eaCC7;
    uint256 constant SPONSORSHIP_PM_UNACCOUNTED_GAS = 50_000;
    uint256 constant TOKEN_PM_UNACCOUNTED_GAS = 95_000;
    uint256 constant PAYMASTER_ID_WITHDRAWAL_DELAY = 3600; // 1 hour
    address constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    mapping (uint256 chainId => TokenPMConfig) public tokenPMConfigs;

    Create3Deployer create3Deployer;

    
    function setUp() public {
        create3Deployer = Create3Deployer(vm.envAddress("CREATE3_DEPLOYER_ADDRESS"));

        _fillTokenPMConfigs();

    }

    function run(bool check, uint256 minDeposit) public {
        if (check) {
            checkGasDaddyAddresses(minDeposit);
        } else {
            vm.startBroadcast();
            deployGasDaddy(minDeposit);
            vm.stopBroadcast();
        }
    }

    function checkGasDaddyAddresses(uint256 minDeposit) public {

        ///
        /// SPONSORSHIP PAYMASTER
        ///
        address sponsorshipPM = create3Deployer.addressOf(SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT);

        uint256 codeSize;
        assembly {
            codeSize := extcodesize(sponsorshipPM)
        }

        console.log("Sponsorship Paymaster address: ", sponsorshipPM, " || >> Code Size: ", codeSize);

        bytes memory args = abi.encode(
          VERIFYING_PAYMASTER_OWNER,
          ENTRY_POINT_V07,
          VERIFYING_SIGNER,
          FEE_COLLECTOR,
          SPONSORSHIP_PM_UNACCOUNTED_GAS,  
          PAYMASTER_ID_WITHDRAWAL_DELAY,
          minDeposit
        );
        console.log("args abi encoded for sponsorship PM: ");
        console.logBytes(args);

        ///
        /// TOKEN PAYMASTER
        ///
        address tokenPM = create3Deployer.addressOf(TOKEN_PAYMASTER_DEPLOYMENT_SALT);
        codeSize;
        assembly {
            codeSize := extcodesize(tokenPM)
        }
        console.log("Token Paymaster address: ", tokenPM, " || >> Code Size: ", codeSize);

        TokenPMConfig memory config = tokenPMConfigs[block.chainid];
        args = abi.encode(
            VERIFYING_PAYMASTER_OWNER,     
            VERIFYING_SIGNER,
            ENTRY_POINT_V07,
            TOKEN_PM_UNACCOUNTED_GAS,
            config.nativeAssetDecimals,
            config.nativeAssetToUsdOracle,
            config.nativeAssetPriceExpiryDuration,
            config.swapRouter,
            config.wrappedNativeAddress,
            config.independentTokens,
            config.tokenInfos,
            new address[](0), // swappable tokens
            new uint24[](0) // swappable token fees
        );
        console.log("args abi encoded for token PM: ");
        console.logBytes(args);
    }   

    //
    // DEPLOY GASDADDY
    //

    function deployGasDaddy(uint256 minDeposit) public returns (uint256 contractsDeployedCount) {

        uint256 create3deployerOwnerPk = vm.envUint("CREATE3_OWNER_PK");

        //
        // SPONSORSHIP PAYMASTER
        //
        bytes memory bytecode = vm.getCode("scripts/bash-deploy/artifacts/BiconomySponsorshipPaymaster/BiconomySponsorshipPaymaster.json");
        bytes memory args = abi.encode(
          VERIFYING_PAYMASTER_OWNER,
          ENTRY_POINT_V07,
          VERIFYING_SIGNER,
          FEE_COLLECTOR,
          SPONSORSHIP_PM_UNACCOUNTED_GAS,  
          PAYMASTER_ID_WITHDRAWAL_DELAY,
          minDeposit
        );
        address sponsorshipPM = create3Deployer.addressOf(SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT);
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(sponsorshipPM)
        }
        if (codeSize > 0) {
            console.log("Sponsorship Paymaster already deployed at", sponsorshipPM);
        } else {
            bytes memory initcode = abi.encodePacked(bytecode, args);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(create3deployerOwnerPk, keccak256(abi.encode(initcode, SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT, block.chainid)));
            sponsorshipPM = create3Deployer.deploy(SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT, initcode, abi.encodePacked(r, s, v));
            console.log("Sponsorship Paymaster deployed at", sponsorshipPM);
            contractsDeployedCount++;
        }

        ///
        /// TOKEN PAYMASTER
        ///

        bytecode = vm.getCode("scripts/bash-deploy/artifacts/BiconomyTokenPaymaster/BiconomyTokenPaymaster.json");
        TokenPMConfig memory config = tokenPMConfigs[block.chainid];
        if (config.nativeAssetDecimals == uint256(0)) {
            console.log("No token PM config found for chain id", block.chainid);
            console.log("Skipping token PM deployment");
            return contractsDeployedCount;
        }

        args = abi.encode(
            VERIFYING_PAYMASTER_OWNER,     
            VERIFYING_SIGNER,
            ENTRY_POINT_V07,
            TOKEN_PM_UNACCOUNTED_GAS,
            config.nativeAssetDecimals,
            config.nativeAssetToUsdOracle,
            config.nativeAssetPriceExpiryDuration,
            config.swapRouter,
            config.wrappedNativeAddress,
            config.independentTokens,
            config.tokenInfos,
            new address[](0), // swappable tokens
            new uint24[](0) // swappable token fees
        );

        address tokenPM = create3Deployer.addressOf(TOKEN_PAYMASTER_DEPLOYMENT_SALT);
        codeSize;
        assembly {
            codeSize := extcodesize(tokenPM)
        }
        if (codeSize > 0) {
            console.log("Token Paymaster already deployed at", tokenPM);
            return contractsDeployedCount;
        } else {
            bytes memory initcode = abi.encodePacked(bytecode, args);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(create3deployerOwnerPk, keccak256(abi.encode(initcode, TOKEN_PAYMASTER_DEPLOYMENT_SALT, block.chainid)));
            tokenPM = create3Deployer.deploy(TOKEN_PAYMASTER_DEPLOYMENT_SALT, initcode, abi.encodePacked(r, s, v));
            console.log("Token Paymaster deployed at", tokenPM);
            contractsDeployedCount++;
        }
    }

    function _fillTokenPMConfigs() internal {
        // in case we want to support independent tokens
        /*
        address[] memory independentTokens = new address[](1);
        independentTokens[0] = address(0);

        IBiconomyTokenPaymaster.TokenInfo[] memory tokenInfos = new IBiconomyTokenPaymaster.TokenInfo[](1);
        tokenInfos[0] = IBiconomyTokenPaymaster.TokenInfo( 
            address(0), // oracle
            0, // priceMarkup
            0 // priceExpiryDuration
        ); */

        // ETHEREUM MAINNET
        tokenPMConfigs[1] = TokenPMConfig(
            address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419), // nativeAssetToUsdOracle
            1e18, // nativeAssetDecimalsMultiplier
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // wrappedNativeAddress
            address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // ETHEREUM SEPOLIA
        tokenPMConfigs[11155111] = TokenPMConfig(
            address(0x694AA1769357215DE4FAC081bf1f309aDC325306), // nativeAssetToUsdOracle
            1e18, // nativeAssetDecimalsMultiplier  
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9), // wrappedNativeAddress
            address(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // BASE MAINNET
        tokenPMConfigs[8453] = TokenPMConfig(
            address(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70), // nativeAssetToUsdOracle
            1e18, // nativeAssetDecimalsMultiplier  
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x4200000000000000000000000000000000000006), // wrappedNativeAddress
            address(0x2626664c2603336E57B271c5C0b26F421741e481), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // BASE SEPOLIA
        tokenPMConfigs[84532] = TokenPMConfig(
            address(0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1), // nativeAssetToUsdOracle
            1e18, // nativeAssetDecimalsMultiplier  
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x4200000000000000000000000000000000000006), // wrappedNativeAddress
            address(0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // ARBITRUM ONE
        tokenPMConfigs[42161] = TokenPMConfig(
            address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612), // nativeAssetToUsdOracle
            1e18, // nativeAssetDecimalsMultiplier  
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1), // wrappedNativeAddress
            address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // ARBITRUM SEPOLIA
        tokenPMConfigs[421614] = TokenPMConfig(
            address(0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165), // nativeAssetToUsdOracle
            1e18, // nativeAssetDecimalsMultiplier  
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x980B62Da83eFf3D4576C647993b0c1D7faf17c73), // wrappedNativeAddress
            address(0x101F443B4d1b059569D643917553c771E1b9663E), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // POLYGON MAINNET
        tokenPMConfigs[137] = TokenPMConfig(
            address(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0), // nativeAssetToUsdOracle (MATIC/USD)
            1e18, // nativeAssetDecimalsMultiplier      
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270), // wrappedNativeAddress // Wrapped MATIC
            address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // POLYGON AMOY
        // Deploy WMATIC on Polygon Amoy
        WETH9 wMATIC = new WETH9();
        tokenPMConfigs[80001] = TokenPMConfig(
            address(0x001382149eBa3441043c1c66972b4772963f5D43), // nativeAssetToUsdOracle // MATIC/USD
            1e18, // nativeAssetDecimalsMultiplier      
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(wMATIC), // wrappedNativeAddress 
            address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // OPTIMISM MAINNET
        tokenPMConfigs[10] = TokenPMConfig(
            address(0x13e3Ee699D1909E989722E753853AE30b17e08c5), // nativeAssetToUsdOracle
            1e18, // nativeAssetDecimalsMultiplier      
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x4200000000000000000000000000000000000006), // wrappedNativeAddress
            address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // OPTIMISM SEPOLIA
        tokenPMConfigs[11155420] = TokenPMConfig(
            address(0x61Ec26aA57019C486B10502285c5A3D4A4750AD7), // nativeAssetToUsdOracle
            1e18, // nativeAssetDecimalsMultiplier      
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x1BDD24840e119DC2602dCC587Dd182812427A5Cc), // wrappedNativeAddress
            address(0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // SCROLL MAINNET
        tokenPMConfigs[534352] = TokenPMConfig(
            address(0x6bF14CB0A831078629D993FDeBcB182b21A8774C), // nativeAssetToUsdOracle
            1e18, // nativeAssetDecimalsMultiplier      
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x5300000000000000000000000000000000000004), // wrappedNativeAddress
            address(0), // NO SWAP ROUTER ON SCROLL <= OWNER CAN SET IT WHEN IT IS DEPLOYED
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // SCROLL SEPOLIA
        tokenPMConfigs[534351] = TokenPMConfig(
            address(0x59F1ec1f10bD7eD9B938431086bC1D9e233ECf41), // nativeAssetToUsdOracle
            1e18, // nativeAssetDecimalsMultiplier
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x5300000000000000000000000000000000000004), // wrappedNativeAddress
            address(0), // NO SWAP ROUTER ON SCROLL SEPOLIA <= OWNER CAN SET IT WHEN IT IS DEPLOYED
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // GNOSIS MAINNET
        tokenPMConfigs[100] = TokenPMConfig(
            address(0x678df3415fc31947dA4324eC63212874be5a82f8), // nativeAssetToUsdOracle DAI/USD
            1e18, // nativeAssetDecimalsMultiplier
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d), // wrappedNativeAddress WXDAI
            address(0x0000000000000000000000000000000000000000), // NO SWAP ROUTER ON GNOSIS <= OWNER CAN SET IT WHEN IT IS DEPLOYED
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // GNOSIS CHIADO
        // SKIP CHIADO AS THERE's NO DAI PRICE FEED THERE

        // BSC MAINNET
        tokenPMConfigs[56] = TokenPMConfig(
            address(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE), // nativeAssetToUsdOracle BNB/USD
            1e18, // nativeAssetDecimalsMultiplier
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c), // wrappedNativeAddress
            address(0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // BSC TESTNET
        tokenPMConfigs[97] = TokenPMConfig(
            address(0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526), // nativeAssetToUsdOracle bnb/usd
            1e18, // nativeAssetDecimalsMultiplier
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x0dE8FCAE8421fc79B29adE9ffF97854a424Cad09), // wrappedNativeAddress /WBNB
            address(0x0000000000000000000000000000000000000000), // NO SWAP ROUTER ON BSC TESTNET <= OWNER CAN SET IT WHEN (IF) IT IS DEPLOYED
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // SKIP BERACHAIN AS THERE's NO ETH/USD PRICE FEED THERE

        // ANVIL
        MockOracle mockNativeOracle;
        if (block.chainid == 31337) {
            //deploy an oracle
            vm.startBroadcast();
            mockNativeOracle = new MockOracle(100_000_000, 8);
            vm.stopBroadcast();
        }
        tokenPMConfigs[31337] = TokenPMConfig(
            address(mockNativeOracle), // nativeAssetToUsdOracle
            1e18, // nativeAssetDecimalsMultiplier
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x4200000000000000000000000000000000000006), // wrappedNativeAddress
            address(2), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

    }
}