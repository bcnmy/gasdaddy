import { BytesLike, HDNodeWallet, Signer } from "ethers";
import { deployments, ethers } from "hardhat";
import { AccountFactory, BiconomySponsorshipPaymaster, EntryPoint, MockValidator, SmartAccount } from "../../../typechain-types";
import { TASK_DEPLOY } from "hardhat-deploy";
import { DeployResult } from "hardhat-deploy/dist/types";

export const ENTRY_POINT_V7 = "0x0000000071727De22E5E9d8BAf0edAc6f37da032";

/**
 * Generic function to deploy a contract using ethers.js.
 *
 * @param contractName The name of the contract to deploy.
 * @param deployer The Signer object representing the deployer account.
 * @returns A promise that resolves to the deployed contract instance.
 */
export async function deployContract<T>(
    contractName: string,
    deployer: Signer,
  ): Promise<T> {
    const ContractFactory = await ethers.getContractFactory(
      contractName,
      deployer,
    );
    const contract = await ContractFactory.deploy();
    await contract.waitForDeployment();
    return contract as T;
}

/**
 * Deploys the EntryPoint contract with a deterministic deployment.
 * @returns A promise that resolves to the deployed EntryPoint contract instance.
 */
export async function getDeployedEntrypoint() : Promise<EntryPoint> {
    const [deployer] = await ethers.getSigners();
  
    // Deploy the contract normally to get its bytecode
    const EntryPoint = await ethers.getContractFactory("EntryPoint");
    const entryPoint = await EntryPoint.deploy();
    await entryPoint.waitForDeployment();
  
    // Retrieve the deployed contract bytecode
    const deployedCode = await ethers.provider.getCode(
      await entryPoint.getAddress(),
    );
  
    // Use hardhat_setCode to set the contract code at the specified address
    await ethers.provider.send("hardhat_setCode", [ENTRY_POINT_V7, deployedCode]);
  
    return EntryPoint.attach(ENTRY_POINT_V7) as EntryPoint;
}

/**
 * Deploys the (MSA) Smart Account implementation contract with a deterministic deployment.
 * @returns A promise that resolves to the deployed SA implementation contract instance.
 */
export async function getDeployedMSAImplementation(): Promise<SmartAccount> {
    const accounts: Signer[] = await ethers.getSigners();
    const addresses = await Promise.all(
        accounts.map((account) => account.getAddress()),
    );
    
    const SmartAccount = await ethers.getContractFactory("SmartAccount");
    const deterministicMSAImpl = await deployments.deploy("SmartAccount", {
        from: addresses[0],
        deterministicDeployment: true,
    });
    
    return SmartAccount.attach(deterministicMSAImpl.address) as SmartAccount;
}

/**
 * Deploys the AccountFactory contract with a deterministic deployment.
 * @returns A promise that resolves to the deployed EntryPoint contract instance.
 */
export async function getDeployedAccountFactory(
    implementationAddress: string,
    // Note: this could be converted to dto so that additional args can easily be passed
  ): Promise<AccountFactory> {
    const accounts: Signer[] = await ethers.getSigners();
    const addresses = await Promise.all(
      accounts.map((account) => account.getAddress()),
    );
  
    const AccountFactory = await ethers.getContractFactory("AccountFactory");
    const deterministicAccountFactory = await deployments.deploy(
      "AccountFactory",
      {
        from: addresses[0],
        deterministicDeployment: true,
        args: [implementationAddress],
      },
    );
  
    return AccountFactory.attach(
      deterministicAccountFactory.address,
    ) as AccountFactory;
}

/**
 * Deploys the MockValidator contract with a deterministic deployment.
 * @returns A promise that resolves to the deployed MockValidator contract instance.
 */
export async function getDeployedMockValidator(): Promise<MockValidator> {
    const accounts: Signer[] = await ethers.getSigners();
    const addresses = await Promise.all(
      accounts.map((account) => account.getAddress()),
    );
  
    const MockValidator = await ethers.getContractFactory("MockValidator");
    const deterministicMockValidator = await deployments.deploy("MockValidator", {
      from: addresses[0],
      deterministicDeployment: true,
    });
  
    return MockValidator.attach(
      deterministicMockValidator.address,
    ) as MockValidator;
}

/**
 * Deploys the MockValidator contract with a deterministic deployment.
 * @returns A promise that resolves to the deployed MockValidator contract instance.
 */
export async function getDeployedSponsorshipPaymaster(owner: string, entryPoint: string, verifyingSigner: string, feeCollector: string): Promise<BiconomySponsorshipPaymaster> {
    const accounts: Signer[] = await ethers.getSigners();
    const addresses = await Promise.all(
      accounts.map((account) => account.getAddress()),
    );
  
    const BiconomySponsorshipPaymaster = await ethers.getContractFactory("BiconomySponsorshipPaymaster");
    const deterministicSponsorshipPaymaster = await deployments.deploy("BiconomySponsorshipPaymaster", {
      from: addresses[0],
      deterministicDeployment: true,
      args: [owner, entryPoint, verifyingSigner, feeCollector],
    });
  
    return BiconomySponsorshipPaymaster.attach(
    deterministicSponsorshipPaymaster.address,
    ) as BiconomySponsorshipPaymaster;
}

