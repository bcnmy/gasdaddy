import { ethers } from "hardhat";
import { expect } from "chai";
import {
  AbiCoder,
  AddressLike,
  BytesLike,
  Signer,
  parseEther,
  toBeHex,
} from "ethers";
import {
  EntryPoint,
  EntryPoint__factory,
  MockValidator,
  MockValidator__factory,
  SmartAccount,
  SmartAccount__factory,
  AccountFactory,
  AccountFactory__factory,
  BiconomySponsorshipPaymaster,
  BiconomySponsorshipPaymaster__factory,
} from "../../typechain-types";

import {
  DefaultsForUserOp,
  fillAndSign,
  fillSignAndPack,
  packUserOp,
  simulateValidation,
} from "./utils/userOpHelpers";
import { parseValidationData } from "./utils/testUtils";

export const AddressZero = ethers.ZeroAddress;

const MOCK_VALID_UNTIL = "0x00000000deadbeef";
const MOCK_VALID_AFTER = "0x0000000000001234";
const MARKUP = 1100000;
export const ENTRY_POINT_V7 = "0x0000000071727De22E5E9d8BAf0edAc6f37da032";

const coder = AbiCoder.defaultAbiCoder();

export async function deployEntryPoint(
  provider = ethers.provider,
): Promise<EntryPoint> {
  const epf = await (await ethers.getContractFactory("EntryPoint")).deploy();
  // Retrieve the deployed contract bytecode
  const deployedCode = await ethers.provider.getCode(await epf.getAddress());

  // Use hardhat_setCode to set the contract code at the specified address
  await ethers.provider.send("hardhat_setCode", [ENTRY_POINT_V7, deployedCode]);

  return epf.attach(ENTRY_POINT_V7) as EntryPoint;
}

describe("EntryPoint with Biconomy Sponsorship Paymaster", function () {
  let entryPoint: EntryPoint;
  let depositorSigner: Signer;
  let walletOwner: Signer;
  let walletAddress: string, paymasterAddress: string;
  let paymasterDepositorId: string;
  let ethersSigner: Signer[];
  let offchainSigner: Signer, deployer: Signer, feeCollector: Signer;
  let paymaster: BiconomySponsorshipPaymaster;
  let smartWalletImp: SmartAccount;
  let ecdsaModule: MockValidator;
  let walletFactory: AccountFactory;

  beforeEach(async function () {
    ethersSigner = await ethers.getSigners();
    entryPoint = await deployEntryPoint();

    deployer = ethersSigner[0];
    offchainSigner = ethersSigner[1];
    depositorSigner = ethersSigner[2];
    feeCollector = ethersSigner[3];
    walletOwner = deployer;

    paymasterDepositorId = await depositorSigner.getAddress();

    const offchainSignerAddress = await offchainSigner.getAddress();
    const walletOwnerAddress = await walletOwner.getAddress();
    const feeCollectorAddess = await feeCollector.getAddress();

    ecdsaModule = await new MockValidator__factory(deployer).deploy();

    paymaster = await new BiconomySponsorshipPaymaster__factory(
      deployer,
    ).deploy(
      await deployer.getAddress(),
      await entryPoint.getAddress(),
      offchainSignerAddress,
      feeCollectorAddess,
    );

    smartWalletImp = await new SmartAccount__factory(deployer).deploy();

    walletFactory = await new AccountFactory__factory(deployer).deploy(
      await smartWalletImp.getAddress(),
    );

    await walletFactory
      .connect(deployer)
      .addStake(86400, { value: parseEther("2") });

    const smartAccountDeploymentIndex = 0;

    // Module initialization data, encoded
    const moduleInstallData = ethers.solidityPacked(
      ["address"],
      [walletOwnerAddress],
    );

    await walletFactory.createAccount(
      await ecdsaModule.getAddress(),
      moduleInstallData,
      smartAccountDeploymentIndex,
    );

    const expected = await walletFactory.getCounterFactualAddress(
      await ecdsaModule.getAddress(),
      moduleInstallData,
      smartAccountDeploymentIndex,
    );

    walletAddress = expected;

    paymasterAddress = await paymaster.getAddress();

    await paymaster
      .connect(deployer)
      .addStake(86400, { value: parseEther("2") });

    await paymaster.depositFor(paymasterDepositorId, {
      value: parseEther("1"),
    });

    await entryPoint.depositTo(paymasterAddress, { value: parseEther("1") });

    await deployer.sendTransaction({
      to: expected,
      value: parseEther("1"),
      data: "0x",
    });
  });

  describe("Deployed Account : #validatePaymasterUserOp and #sendEmptySponsoredTx", () => {
    it("succeed with valid signature", async () => {
      const nonceKey = ethers.zeroPadBytes(await ecdsaModule.getAddress(), 24);
      const userOp1 = await fillAndSign(
        {
          sender: walletAddress,
          paymaster: paymasterAddress,
          paymasterData: ethers.concat([
            ethers.zeroPadValue(paymasterDepositorId, 20),
            ethers.zeroPadValue(toBeHex(MOCK_VALID_UNTIL), 6),
            ethers.zeroPadValue(toBeHex(MOCK_VALID_AFTER), 6),
            ethers.zeroPadValue(toBeHex(MARKUP), 4),
            "0x" + "00".repeat(65),
          ]),
          paymasterPostOpGasLimit: 40_000,
        },
        walletOwner,
        entryPoint,
        "getNonce",
        nonceKey,
      );
      const hash = await paymaster.getHash(
        packUserOp(userOp1),
        paymasterDepositorId,
        MOCK_VALID_UNTIL,
        MOCK_VALID_AFTER,
        MARKUP,
      );
      const sig = await offchainSigner.signMessage(ethers.getBytes(hash));
      const userOp = await fillSignAndPack(
        {
          ...userOp1,
          paymaster: paymasterAddress,
          paymasterData: ethers.concat([
            ethers.zeroPadValue(paymasterDepositorId, 20),
            ethers.zeroPadValue(toBeHex(MOCK_VALID_UNTIL), 6),
            ethers.zeroPadValue(toBeHex(MOCK_VALID_AFTER), 6),
            ethers.zeroPadValue(toBeHex(MARKUP), 4),
            sig,
          ]),
          paymasterPostOpGasLimit: 40_000,
        },
        walletOwner,
        entryPoint,
        "getNonce",
        nonceKey,
      );
      // const parsedPnD = await paymaster.parsePaymasterAndData(userOp.paymasterAndData)
      const res = await simulateValidation(
        userOp,
        await entryPoint.getAddress(),
      );
      const validationData = parseValidationData(
        res.returnInfo.paymasterValidationData,
      );
      expect(validationData).to.eql({
        aggregator: AddressZero,
        validAfter: parseInt(MOCK_VALID_AFTER),
        validUntil: parseInt(MOCK_VALID_UNTIL),
      });

      await entryPoint.handleOps([userOp], await deployer.getAddress());
    });
  });
});
