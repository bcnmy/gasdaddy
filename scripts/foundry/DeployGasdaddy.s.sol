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
    bytes32 constant SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT = 0x3e81534a95d3368136d6c49522f8e20ada0b768931512a65c785c15a83178526; // PM Address => 0x00000028d034c96fb11b5cfc856535f84866035b
    bytes32 constant TOKEN_PAYMASTER_DEPLOYMENT_SALT = 0xf5516e76713013dc560228c61d8ad21680be770b25fcaed28edf3071e09bbd25; // PM Address => 0x00000023f4bb8e932538360023e6d8da15fb9711

    // CREATE3 DEPLOYER ADDRESS
    address constant CREATE3_DEPLOYER_ADDRESS = 0x000000aFCC4940A247A53bEa5f3f4602433fe815;

    // CONSTRUCTOR ARGS
    address constant VERIFYING_PAYMASTER_OWNER = 0x2cf491602ad22944D9047282aBC00D3e52F56B37;
    address constant VERIFYING_SIGNER = 0xC6dAB8652E5E9749523bA948F42d5944584E4e73;
    address constant FEE_COLLECTOR = 0x2cf491602ad22944D9047282aBC00D3e52F56B37;
    uint256 constant SPONSORSHIP_PM_UNACCOUNTED_GAS = 50_000;
    uint256 constant TOKEN_PM_UNACCOUNTED_GAS = 95_000;
    uint256 constant PAYMASTER_ID_WITHDRAWAL_DELAY = 3600; // 1 hour
    address constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    mapping (uint256 => bytes) public signaturesForMinDeposits;
    mapping (uint256 chainId => TokenPMConfig) public tokenPMConfigs;

    Create3Deployer create3Deployer;

    
    function setUp() public {
        create3Deployer = Create3Deployer(CREATE3_DEPLOYER_ADDRESS);

        _fillSignaturesForMinDepositsSponsPM();

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

        // Use this block to get initcode hashes to sign
        /* 
        uint256[] memory minDeposits = new uint256[](5);
        minDeposits[0] = 1e15;
        minDeposits[1] = 1e16;
        minDeposits[2] = 1e17;
        minDeposits[3] = 1e18;
        minDeposits[4] = 1e19;

        for (uint256 i = 0; i < minDeposits.length; i++) {
            minDeposit = minDeposits[i];
            args = abi.encode(
              VERIFYING_PAYMASTER_OWNER,
              ENTRY_POINT_V07,
              VERIFYING_SIGNER,
              FEE_COLLECTOR,
              UNACCOUNTED_GAS,
              PAYMASTER_ID_WITHDRAWAL_DELAY,
              minDeposit
            );
            console.log("min deposit: ", (minDeposit));
            console.logBytes32(keccak256(abi.encodePacked(bytecode, args)));
        }
        */

        ///
        /// TOKEN PAYMASTER
        ///
        address tokenPM = create3Deployer.addressOf(TOKEN_PAYMASTER_DEPLOYMENT_SALT);
        codeSize;
        assembly {
            codeSize := extcodesize(tokenPM)
        }
        console.log("Token Paymaster address: ", tokenPM, " || >> Code Size: ", codeSize);
    }   

    function deployGasDaddy(uint256 minDeposit) public returns (uint256 contractsDeployedCount) {

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
            bytes memory signature = signaturesForMinDeposits[minDeposit];
            sponsorshipPM = create3Deployer.deploy(SPONSORSHIP_PAYMASTER_DEPLOYMENT_SALT, initcode, signature);
            console.log("Sponsorship Paymaster deployed at", sponsorshipPM);
            contractsDeployedCount++;
        }

        ///
        /// TOKEN PAYMASTER
        ///
        uint256 create3deployerOwnerPk = vm.envUint("CREATE3_OWNER_PK");

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
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(create3deployerOwnerPk, keccak256(initcode));
            tokenPM = create3Deployer.deploy(TOKEN_PAYMASTER_DEPLOYMENT_SALT, initcode, abi.encodePacked(r, s, v));
            console.log("Token Paymaster deployed at", tokenPM);
            contractsDeployedCount++;
        }
    }

    function _fillSignaturesForMinDepositsSponsPM() internal {
                // Signatures for Sponsorship PM  
        signaturesForMinDeposits[1e15] = hex'f799f0e37b89b42d667d6cf6ca461bb4e1d9818a5568a640ad89dbe74a16b18b105a3ecbe06828faaf91153bf2238bd5bf9f52cda834eb2ddc81c5665b77901f1b'; //0.001 native token
        signaturesForMinDeposits[1e16] = hex'3d4fc4d9a447fb205cc50dce4b74230f0e0baea776bbce2cced39e1b82f612bc5de05607fdeaf3734f8577a8b829b0dd05bb0fe760e4fe9dda28b729d45c95d21c'; //0.01 native token
        signaturesForMinDeposits[1e17] = hex'f121c54fabc0f95a2baa1cc296135d125f636532d489a9850a0ea3fe7f52694a2954b6f5cd42aca1e2203e7e39108a878477bfe2f90ed6a38ec578199e5586111c'; //0.1 native token
        signaturesForMinDeposits[1e18] = hex'0e2f4921b34b8a2a6ceab67bd7db9655c0e272a725cbb5da84acaad1d023237817a1cb754fd65dd45bebc43312dafb9b53c8e58619da7da5acc9ea96294534141b'; //1 native token
        signaturesForMinDeposits[1e19] = hex'6e559e01580bc8cd18fabef2d0aa018f35dc5cb1aa0c26e8cb8b9c45478382cf0fcc208ad2564d693418957e417a90b9081716fa1c01cba65e8442edaed584541c'; //10 native tokens
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
            18, // nativeAssetDecimals
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // wrappedNativeAddress
            address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // ETHEREUM SEPOLIA
        tokenPMConfigs[11155111] = TokenPMConfig(
            address(0x694AA1769357215DE4FAC081bf1f309aDC325306), // nativeAssetToUsdOracle
            18, // nativeAssetDecimals
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9), // wrappedNativeAddress
            address(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // BASE MAINNET
        tokenPMConfigs[8453] = TokenPMConfig(
            address(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70), // nativeAssetToUsdOracle
            18, // nativeAssetDecimals
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x4200000000000000000000000000000000000006), // wrappedNativeAddress
            address(0x2626664c2603336E57B271c5C0b26F421741e481), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // BASE SEPOLIA
        tokenPMConfigs[84532] = TokenPMConfig(
            address(0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1), // nativeAssetToUsdOracle
            18, // nativeAssetDecimals
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x4200000000000000000000000000000000000006), // wrappedNativeAddress
            address(0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // ARBITRUM ONE
        tokenPMConfigs[42161] = TokenPMConfig(
            address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612), // nativeAssetToUsdOracle
            18, // nativeAssetDecimals
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1), // wrappedNativeAddress
            address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // ARBITRUM SEPOLIA
        tokenPMConfigs[421614] = TokenPMConfig(
            address(0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165), // nativeAssetToUsdOracle
            18, // nativeAssetDecimals
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x980B62Da83eFf3D4576C647993b0c1D7faf17c73), // wrappedNativeAddress
            address(0x101F443B4d1b059569D643917553c771E1b9663E), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

        // POLYGON MAINNET
        tokenPMConfigs[137] = TokenPMConfig(
            address(0xF9680D99D6C9589e2a93a78A04A279e509205945), // nativeAssetToUsdOracle
            18, // nativeAssetDecimals
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
            address(0xF0d50568e3A7e8259E16663972b11910F89BD8e7), // nativeAssetToUsdOracle
            18, // nativeAssetDecimals
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(wMATIC), // wrappedNativeAddress 
            address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

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
            18, // nativeAssetDecimals
            3600, // nativeAssetPriceExpiryDuration // 1 hour
            address(0x4200000000000000000000000000000000000006), // wrappedNativeAddress
            address(2), // swapRouter
            new address[](0),
            new IBiconomyTokenPaymaster.TokenInfo[](0)
        );

    }
}
