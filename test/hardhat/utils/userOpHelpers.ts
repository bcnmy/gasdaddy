import { ethers } from "hardhat";
import {
  EntryPoint,
  EntryPointSimulations__factory,
  IEntryPointSimulations,
} from "../../../typechain-types";
import { PackedUserOperation, UserOperation } from "./types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { TransactionRequest } from "@ethersproject/abstract-provider";
import {
  AbiCoder,
  BigNumberish,
  BytesLike,
  Contract,
  Signer,
  dataSlice,
  keccak256,
  toBeHex,
} from "ethers";
import { toGwei } from "./general";
import { callDataCost, decodeRevertReason, rethrow } from "./testUtils";
import EntryPointSimulationsJson from "../../../artifacts/account-abstraction/contracts/core/EntryPointSimulations.sol/EntryPointSimulations.json";

const AddressZero = ethers.ZeroAddress;
const coder = AbiCoder.defaultAbiCoder();

export function packUserOp(userOp: UserOperation): PackedUserOperation {
  const {
    sender,
    nonce,
    initCode = "0x",
    callData = "0x",
    callGasLimit = 1_500_000,
    verificationGasLimit = 1_500_000,
    preVerificationGas = 2_000_000,
    maxFeePerGas = toGwei("20"),
    maxPriorityFeePerGas = toGwei("10"),
    paymaster = ethers.ZeroAddress,
    paymasterData = "0x",
    paymasterVerificationGasLimit = 3_00_000,
    paymasterPostOpGasLimit = 0,
    signature = "0x",
  } = userOp;

  const accountGasLimits = packAccountGasLimits(
    verificationGasLimit,
    callGasLimit,
  );
  const gasFees = packAccountGasLimits(maxPriorityFeePerGas, maxFeePerGas);
  let paymasterAndData = "0x";
  if (paymaster.toString().length >= 20 && paymaster !== ethers.ZeroAddress) {
    paymasterAndData = packPaymasterData(
      userOp.paymaster as string,
      paymasterVerificationGasLimit,
      paymasterPostOpGasLimit,
      paymasterData as string,
    ) as string;
  }
  return {
    sender: userOp.sender,
    nonce: userOp.nonce || 0,
    callData: userOp.callData || "0x",
    accountGasLimits,
    initCode: userOp.initCode || "0x",
    preVerificationGas: userOp.preVerificationGas || 50000,
    gasFees,
    paymasterAndData,
    signature: userOp.signature || "0x",
  };
}

export function encodeUserOp(
  userOp: UserOperation,
  forSignature = true,
): string {
  const packedUserOp = packUserOp(userOp);
  if (forSignature) {
    return coder.encode(
      [
        "address",
        "uint256",
        "bytes32",
        "bytes32",
        "bytes32",
        "uint256",
        "bytes32",
        "bytes32",
      ],
      [
        packedUserOp.sender,
        packedUserOp.nonce,
        keccak256(packedUserOp.initCode),
        keccak256(packedUserOp.callData),
        packedUserOp.accountGasLimits,
        packedUserOp.preVerificationGas,
        packedUserOp.gasFees,
        keccak256(packedUserOp.paymasterAndData),
      ],
    );
  } else {
    // for the purpose of calculating gas cost encode also signature (and no keccak of bytes)
    return coder.encode(
      [
        "address",
        "uint256",
        "bytes",
        "bytes",
        "bytes32",
        "uint256",
        "bytes32",
        "bytes",
        "bytes",
      ],
      [
        packedUserOp.sender,
        packedUserOp.nonce,
        packedUserOp.initCode,
        packedUserOp.callData,
        packedUserOp.accountGasLimits,
        packedUserOp.preVerificationGas,
        packedUserOp.gasFees,
        packedUserOp.paymasterAndData,
        packedUserOp.signature,
      ],
    );
  }
}

// Can be moved to testUtils
export function packPaymasterData(
  paymaster: string,
  paymasterVerificationGasLimit: BigNumberish,
  postOpGasLimit: BigNumberish,
  paymasterData: BytesLike,
): BytesLike {
  return ethers.concat([
    paymaster,
    ethers.zeroPadValue(toBeHex(Number(paymasterVerificationGasLimit)), 16),
    ethers.zeroPadValue(toBeHex(Number(postOpGasLimit)), 16),
    paymasterData,
  ]);
}

// Can be moved to testUtils
export function packAccountGasLimits(
  verificationGasLimit: BigNumberish,
  callGasLimit: BigNumberish,
): string {
  return ethers.concat([
    ethers.zeroPadValue(toBeHex(Number(verificationGasLimit)), 16),
    ethers.zeroPadValue(toBeHex(Number(callGasLimit)), 16),
  ]);
}

// Can be moved to testUtils
export function unpackAccountGasLimits(accountGasLimits: string): {
  verificationGasLimit: number;
  callGasLimit: number;
} {
  return {
    verificationGasLimit: parseInt(accountGasLimits.slice(2, 34), 16),
    callGasLimit: parseInt(accountGasLimits.slice(34), 16),
  };
}

export function getUserOpHash(
  op: UserOperation,
  entryPoint: string,
  chainId: number,
): string {
  const userOpHash = keccak256(encodeUserOp(op, true));
  const enc = coder.encode(
    ["bytes32", "address", "uint256"],
    [userOpHash, entryPoint, chainId],
  );
  return keccak256(enc);
}

export const DefaultsForUserOp: UserOperation = {
  sender: AddressZero,
  nonce: 0,
  initCode: "0x",
  callData: "0x",
  callGasLimit: 0,
  verificationGasLimit: 150000, // default verification gas. will add create2 cost (3200+200*length) if initCode exists
  preVerificationGas: 21000, // should also cover calldata cost.
  maxFeePerGas: 0,
  maxPriorityFeePerGas: 1e9,
  paymaster: AddressZero,
  paymasterData: "0x",
  paymasterVerificationGasLimit: 3e5,
  paymasterPostOpGasLimit: 0,
  signature: "0x",
};

// Different compared to infinitism utils
export async function signUserOp(
  op: UserOperation,
  signer: Signer,
  entryPoint: string,
  chainId: number,
): Promise<UserOperation> {
  const message = getUserOpHash(op, entryPoint, chainId);

  const signature = await signer.signMessage(ethers.getBytes(message));

  return {
    ...op,
    signature: signature,
  };
}

export function fillUserOpDefaults(
  op: Partial<UserOperation>,
  defaults = DefaultsForUserOp,
): UserOperation {
  const partial: any = { ...op };
  // we want "item:undefined" to be used from defaults, and not override defaults, so we must explicitly
  // remove those so "merge" will succeed.
  for (const key in partial) {
    if (partial[key] == null) {
      // eslint-disable-next-line @typescript-eslint/no-dynamic-delete
      delete partial[key];
    }
  }
  const filled = { ...defaults, ...partial };
  return filled;
}

// helper to fill structure:
// - default callGasLimit to estimate call from entryPoint to account (TODO: add overhead)
// if there is initCode:
//  - calculate sender by eth_call the deployment code
//  - default verificationGasLimit estimateGas of deployment code plus default 100000
// no initCode:
//  - update nonce from account.getNonce()
// entryPoint param is only required to fill in "sender address when specifying "initCode"
// nonce: assume contract as "getNonce()" function, and fill in.
// sender - only in case of construction: fill sender from initCode.
// callGasLimit: VERY crude estimation (by estimating call to account, and add rough entryPoint overhead
// verificationGasLimit: hard-code default at 100k. should add "create2" cost
export async function fillUserOp(
  op: Partial<UserOperation>,
  entryPoint?: EntryPoint,
  getNonceFunction = "getNonce",
  nonceKey = "0",
): Promise<UserOperation | undefined> {
  const op1 = { ...op };
  const provider = ethers.provider;
  if (op.initCode != null && op.initCode !== "0x") {
    const initAddr = dataSlice(op1.initCode!, 0, 20);
    const initCallData = dataSlice(op1.initCode!, 20);
    if (op1.nonce == null) op1.nonce = 0;
    if (op1.sender == null) {
      if (provider == null) throw new Error("no entrypoint/provider");
      op1.sender = await entryPoint!
        .getSenderAddress(op1.initCode!)
        .catch((e) => e.errorArgs.sender);
    }
    if (op1.verificationGasLimit == null) {
      if (provider == null) throw new Error("no entrypoint/provider");
      const initEstimate = await provider.estimateGas({
        from: await entryPoint?.getAddress(),
        to: initAddr,
        data: initCallData,
        gasLimit: 10e6,
      });
      op1.verificationGasLimit =
        Number(DefaultsForUserOp.verificationGasLimit!) + Number(initEstimate);
    }
  }
  if (op1.nonce == null) {
    // TODO: nonce should be fetched from entrypoint based on key
    //   if (provider == null) throw new Error('must have entryPoint to autofill nonce')
    //   const c = new Contract(op.sender! as string, [`function ${getNonceFunction}() view returns(uint256)`], provider)
    //   op1.nonce = await c[getNonceFunction]().catch(rethrow())
    const nonce = await entryPoint?.getNonce(op1.sender!, nonceKey);
    op1.nonce = nonce ?? 0n;
  }
  if (op1.callGasLimit == null && op.callData != null) {
    if (provider == null)
      throw new Error("must have entryPoint for callGasLimit estimate");
    const gasEtimated = await provider.estimateGas({
      from: await entryPoint?.getAddress(),
      to: op1.sender,
      data: op1.callData as string,
    });

    // console.log('estim', op1.sender,'len=', op1.callData!.length, 'res=', gasEtimated)
    // estimateGas assumes direct call from entryPoint. add wrapper cost.
    op1.callGasLimit = gasEtimated; // .add(55000)
  }
  if (op1.paymaster != null) {
    if (op1.paymasterVerificationGasLimit == null) {
      op1.paymasterVerificationGasLimit =
        DefaultsForUserOp.paymasterVerificationGasLimit;
    }
    if (op1.paymasterPostOpGasLimit == null) {
      op1.paymasterPostOpGasLimit = DefaultsForUserOp.paymasterPostOpGasLimit;
    }
  }
  if (op1.maxFeePerGas == null) {
    if (provider == null)
      throw new Error("must have entryPoint to autofill maxFeePerGas");
    const block = await provider.getBlock("latest");
    op1.maxFeePerGas =
      Number(block!.baseFeePerGas!) +
      Number(
        op1.maxPriorityFeePerGas ?? DefaultsForUserOp.maxPriorityFeePerGas,
      );
  }
  // TODO: this is exactly what fillUserOp below should do - but it doesn't.
  // adding this manually
  if (op1.maxPriorityFeePerGas == null) {
    op1.maxPriorityFeePerGas = DefaultsForUserOp.maxPriorityFeePerGas;
  }
  const op2 = fillUserOpDefaults(op1);
  // if(op2 === undefined || op2 === null) {
  //     throw new Error('op2 is undefined or null')
  // }
  // eslint-disable-next-line @typescript-eslint/no-base-to-string
  if (op2?.preVerificationGas?.toString() === "0") {
    // TODO: we don't add overhead, which is ~21000 for a single TX, but much lower in a batch.
    op2.preVerificationGas = callDataCost(encodeUserOp(op2, false));
  }
  return op2;
}

export async function fillAndPack(
  op: Partial<UserOperation>,
  entryPoint?: EntryPoint,
  getNonceFunction = "getNonce",
): Promise<PackedUserOperation | undefined> {
  const userOp = await fillUserOp(op, entryPoint, getNonceFunction);
  if (userOp === undefined) {
    throw new Error("userOp is undefined");
  }
  return packUserOp(userOp);
}

export async function fillAndSign(
  op: Partial<UserOperation>,
  signer: Signer | Signer,
  entryPoint?: EntryPoint,
  getNonceFunction = "getNonce",
  nonceKey = "0",
): Promise<UserOperation> {
  const provider = ethers.provider;
  const op2 = await fillUserOp(op, entryPoint, getNonceFunction, nonceKey);
  if (op2 === undefined) {
    throw new Error("op2 is undefined");
  }

  const chainId = await provider!.getNetwork().then((net) => net.chainId);
  const message = ethers.getBytes(
    getUserOpHash(op2, await entryPoint!.getAddress(), Number(chainId)),
  );

  let signature;
  try {
    signature = await signer.signMessage(message);
  } catch (err: any) {
    // attempt to use 'eth_sign' instead of 'personal_sign' which is not supported by Foundry Anvil
    signature = await (signer as any)._legacySignMessage(message);
  }
  return {
    ...op2,
    signature,
  };
}

export async function fillSignAndPack(
  op: Partial<UserOperation>,
  signer: Signer | Signer,
  entryPoint?: EntryPoint,
  getNonceFunction = "getNonce",
  nonceKey = "0",
): Promise<PackedUserOperation> {
  const filledAndSignedOp = await fillAndSign(
    op,
    signer,
    entryPoint,
    getNonceFunction,
    nonceKey,
  );
  return packUserOp(filledAndSignedOp);
}

/**
 * This function relies on a "state override" functionality of the 'eth_call' RPC method
 * in order to provide the details of a simulated validation call to the bundler
 * @param userOp
 * @param entryPointAddress
 * @param txOverrides
 */
export async function simulateValidation(
  userOp: PackedUserOperation,
  entryPointAddress: string,
  txOverrides?: any,
): Promise<IEntryPointSimulations.ValidationResultStructOutput> {
  const entryPointSimulations =
    EntryPointSimulations__factory.createInterface();
  const data = entryPointSimulations.encodeFunctionData("simulateValidation", [
    userOp,
  ]);
  const tx: TransactionRequest = {
    to: entryPointAddress,
    data,
    ...txOverrides,
  };
  const stateOverride = {
    [entryPointAddress]: {
      code: EntryPointSimulationsJson.deployedBytecode,
    },
  };
  try {
    const simulationResult = await ethers.provider.send("eth_call", [
      tx,
      "latest",
      stateOverride,
    ]);
    const res = entryPointSimulations.decodeFunctionResult(
      "simulateValidation",
      simulationResult,
    );
    // note: here collapsing the returned "tuple of one" into a single value - will break for returning actual tuples
    return res[0];
  } catch (error: any) {
    const revertData = error?.data;
    if (revertData != null) {
      // note: this line throws the revert reason instead of returning it
      entryPointSimulations.decodeFunctionResult(
        "simulateValidation",
        revertData,
      );
    }
    throw error;
  }
}

// TODO: this code is very much duplicated but "encodeFunctionData" is based on 20 overloads
//  TypeScript is not able to resolve overloads with variables: https://github.com/microsoft/TypeScript/issues/14107
export async function simulateHandleOp(
  userOp: PackedUserOperation,
  target: string,
  targetCallData: string,
  entryPointAddress: string,
  txOverrides?: any,
): Promise<IEntryPointSimulations.ExecutionResultStructOutput> {
  const entryPointSimulations =
    EntryPointSimulations__factory.createInterface();
  const data = entryPointSimulations.encodeFunctionData("simulateHandleOp", [
    userOp,
    target,
    targetCallData,
  ]);
  const tx: TransactionRequest = {
    to: entryPointAddress,
    data,
    ...txOverrides,
  };
  const stateOverride = {
    [entryPointAddress]: {
      code: EntryPointSimulationsJson.deployedBytecode,
    },
  };
  try {
    const simulationResult = await ethers.provider.send("eth_call", [
      tx,
      "latest",
      stateOverride,
    ]);
    const res = entryPointSimulations.decodeFunctionResult(
      "simulateHandleOp",
      simulationResult,
    );
    // note: here collapsing the returned "tuple of one" into a single value - will break for returning actual tuples
    return res[0];
  } catch (error: any) {
    const err = decodeRevertReason(error);
    if (err != null) {
      throw new Error(err);
    }
    throw error;
  }
}
