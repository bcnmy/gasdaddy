#!/bin/bash

### VERIFY INPUTS ###
printMan() {
    printf "Usage: $0 <Environment: local|mainnet|testnet> <Network Name>\n"
}

if [ $# -eq 0 ]; then
    printf "Please provide private key, environment and network name\n"
    printMan
    exit 1
fi

if [ -z $1 ]; then
    printf "Please provide environment\n"
    printMan
    exit 1
fi

ENVIRONMENT=$1
VERIFY=""

if [ $ENVIRONMENT = "local" ]; then
    CHAIN_NAME="localhost"
else 
    if [ $ENVIRONMENT = "mainnet" ] || [ $ENVIRONMENT = "testnet" ]; then
        if [ -z $2 ]; then
            printf "Please provide network name\n"
            printMan
            exit 1
        fi
        CHAIN_NAME=$2
        VERIFY="--verify"
    else 
        printf "Invalid environment\n"
        printMan
        exit 1
    fi
fi

source ../../.env

# set private key based on the environment
if [ $ENVIRONMENT = "mainnet" ]; then
    PRIVATE_KEY=$MAINNET_DEPLOYER_PRIVATE_KEY
else 
    if [ $ENVIRONMENT = "testnet" ]; then
        PRIVATE_KEY=$TESTNET_DEPLOYER_PRIVATE_KEY
    else 
        PRIVATE_KEY=$LOCAL_DEPLOYER_PRIVATE_KEY
    fi
fi

### DEPLOY PRE-REQUISITES ###
{ (bash deploy-prerequisites.sh $PRIVATE_KEY $ENVIRONMENT $CHAIN_NAME) } || {
    printf "Deployment prerequisites failed\n"
    exit 1
}

### COPY ARTIFACTS ###
read -r -p "Do you want to rebuild GasDaddy artifacts from your local sources? (y/n): " proceed
if [ $proceed = "y" ]; then
    ### BUILD ARTIFACTS ###
    printf "Building GasDaddy artifacts\n"
    { (forge build 1> ./logs/forge-build.log 2> ./logs/forge-build-errors.log) } || {
        printf "Build failed\n See logs for more details\n"
        exit 1
    }
    printf "Copying Paymasters artifacts\n"
    mkdir -p ./artifacts/BiconomySponsorshipPaymaster
    mkdir -p ./artifacts/BiconomyTokenPaymaster
    cp ../../out/BiconomySponsorshipPaymaster.sol/BiconomySponsorshipPaymaster.json ./artifacts/BiconomySponsorshipPaymaster/.
    cp ../../out/BiconomyTokenPaymaster.sol/BiconomyTokenPaymaster.json ./artifacts/BiconomyTokenPaymaster/.

    printf "Artifacts copied\n"

    ### CREATE VERIFICATION ARTIFACTS ###
    printf "Creating verification artifacts\n"
    
    forge verify-contract --show-standard-json-input $(cast address-zero) BiconomySponsorshipPaymaster > ./artifacts/BiconomySponsorshipPaymaster/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) BiconomyTokenPaymaster > ./artifacts/BiconomyTokenPaymaster/verify.json
    
else 
    printf "Using precompiled artifacts\n"
fi

### Get custom min deposit
read -r -p "Default min deposit param is 0.001 native token. Do you want to specify a custom min deposit? (y/n): " proceed
if [ $proceed = "y" ]; then
    printf "Choose a custom min deposit: \n 1. 0.001 native token \n 2. 0.01 native token \n 3. 0.1 native token \n 4. 1 native token \n 5. 10 native tokens \n"
    read -r -a MIN_DEPOSIT_CHOICE
    if [ $MIN_DEPOSIT_CHOICE = "1" ]; then
        MIN_DEPOSIT=1000000000000000
    elif [ $MIN_DEPOSIT_CHOICE = "2" ]; then
        MIN_DEPOSIT=10000000000000000
    elif [ $MIN_DEPOSIT_CHOICE = "3" ]; then
        MIN_DEPOSIT=100000000000000000
    elif [ $MIN_DEPOSIT_CHOICE = "4" ]; then
        MIN_DEPOSIT=1000000000000000000
    elif [ $MIN_DEPOSIT_CHOICE = "5" ]; then
        MIN_DEPOSIT=10000000000000000000
    fi
else 
    MIN_DEPOSIT=1000000000000000
fi

### DEPLOY GASDADDY SCs ###
printf "Addresses for Paymaster SCs:\n"
forge script DeployGasdaddy true $MIN_DEPOSIT --sig "run(bool,uint256)" --rpc-url $CHAIN_NAME -vv > ./logs/$CHAIN_NAME/$CHAIN_NAME-gasdaddy-predeploy.log
cat ./logs/$CHAIN_NAME/$CHAIN_NAME-gasdaddy-predeploy.log | grep -e "address" -e "already deployed"
printf "Do you want to proceed with the addresses above? (y/n): "
read -r proceed
if [ $proceed = "y" ]; then
    printf "Do you want to specify gas price? (y/n): "
    read -r proceed
    if [ $proceed = "y" ]; then
        printf "Enter gas prices args: \n For the EIP-1559 chains, enter two args: base fee and priority fee in gwei\n For the legacy chains, enter one argument. \n Example eip-1559: 20 1 \n Example legacy: 20 \n"
        read -r -a GAS_ARGS
        if [ ${#GAS_ARGS[@]} -eq 2 ]; then
            GAS_SUFFIX="--with-gas-price ${GAS_ARGS[0]}gwei --priority-gas-price ${GAS_ARGS[1]}gwei"
        else 
            GAS_SUFFIX="--with-gas-price ${GAS_ARGS[0]}gwei"
        fi
    else 
        GAS_SUFFIX=""
    fi
    {   
        printf "Proceeding with deployment \n"
        mkdir -p ./logs/$CHAIN_NAME
        forge script DeployGasdaddy false $MIN_DEPOSIT --sig "run(bool,uint256)" --rpc-url $CHAIN_NAME --etherscan-api-key $CHAIN_NAME --private-key $PRIVATE_KEY $VERIFY -vv --broadcast --slow $GAS_SUFFIX 1> ./logs/$CHAIN_NAME/$CHAIN_NAME-deploy-gasdaddy.log 2> ./logs/$CHAIN_NAME/$CHAIN_NAME-deploy-gasdaddy-errors.log 
    } || {
        printf "Deployment failed\n See logs for more details\n"
        exit 1
    }
    printf "Deployment successful\n"
    cat ./logs/$CHAIN_NAME/$CHAIN_NAME-deploy-gasdaddy.log | grep "deployed at"
else 
    printf "Exiting\n"
    exit 1
fi  