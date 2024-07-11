import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-storage-layout";
import "@bonadocs/docgen";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.26",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000000,
        details: {
          yul: true,
        },
      },
      viaIR: true,
    },
  },
  docgen: {
    projectName: "Biconomy Paymasters",
    projectDescription: "Account Abstraction (v0.7.0) Paymasters",
  },
};

export default config;
