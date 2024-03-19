import { ethers } from "hardhat";

const entryPointAddress =
  process.env.ENTRY_POINT_ADDRESS ||
  "0x0000000071727De22E5E9d8BAf0edAc6f37da032";

const verifyingSigner =
  process.env.PAYMASTER_SIGNER_ADDRESS_PROD ||
  "0x2cf491602ad22944D9047282aBC00D3e52F56B37";

const deployEntryPoint = process.env.DEPLOY_ENTRY_POINT || true;

async function main() {
  let targetEntryPoint = entryPointAddress;

  if (deployEntryPoint) {
    // Note: unless the network is actual chain where entrypoint is deployed, we have to deploy for hardhat node tests
    const entryPoint = await ethers.deployContract("EntryPoint");

    await entryPoint.waitForDeployment();

    targetEntryPoint = entryPoint.target as string;

    console.log(`EntryPoint updated to ${entryPoint.target}`);
  }

  const verifyingPaymaster = await ethers.deployContract("VerifyingPaymaster", [
    targetEntryPoint,
    verifyingSigner,
  ]);

  await verifyingPaymaster.waitForDeployment();

  console.log(`VerifyingPaymaster deployed to ${verifyingPaymaster.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
