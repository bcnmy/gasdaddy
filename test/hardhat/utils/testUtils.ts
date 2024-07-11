import {
  AbiCoder,
  AddressLike,
  BigNumberish,
  Contract,
  Interface,
  dataSlice,
  parseEther,
  toBeHex,
} from "ethers";
import { ethers } from "hardhat";
import { EntryPoint__factory, IERC20 } from "../../../typechain-types";

// define mode and exec type enums
export const CALLTYPE_SINGLE = "0x00"; // 1 byte
export const CALLTYPE_BATCH = "0x01"; // 1 byte
export const EXECTYPE_DEFAULT = "0x00"; // 1 byte
export const EXECTYPE_TRY = "0x01"; // 1 byte
export const EXECTYPE_DELEGATE = "0xFF"; // 1 byte
export const MODE_DEFAULT = "0x00000000"; // 4 bytes
export const UNUSED = "0x00000000"; // 4 bytes
export const MODE_PAYLOAD = "0x00000000000000000000000000000000000000000000"; // 22 bytes

export const AddressZero = ethers.ZeroAddress;
export const HashZero = ethers.ZeroHash;
export const ONE_ETH = parseEther("1");
export const TWO_ETH = parseEther("2");
export const FIVE_ETH = parseEther("5");
export const maxUint48 = 2 ** 48 - 1;

export const tostr = (x: any): string => (x != null ? x.toString() : "null");

const coder = AbiCoder.defaultAbiCoder();

export interface ValidationData {
  aggregator: string;
  validAfter: number;
  validUntil: number;
}

export const panicCodes: { [key: number]: string } = {
  // from https://docs.soliditylang.org/en/v0.8.0/control-structures.html
  0x01: "assert(false)",
  0x11: "arithmetic overflow/underflow",
  0x12: "divide by zero",
  0x21: "invalid enum value",
  0x22: "storage byte array that is incorrectly encoded",
  0x31: ".pop() on an empty array.",
  0x32: "array sout-of-bounds or negative index",
  0x41: "memory overflow",
  0x51: "zero-initialized variable of internal function type",
};
export const Erc20 = [
  "function transfer(address _receiver, uint256 _value) public returns (bool success)",
  "function transferFrom(address, address, uint256) public returns (bool)",
  "function approve(address _spender, uint256 _value) public returns (bool success)",
  "function allowance(address _owner, address _spender) public view returns (uint256 remaining)",
  "function balanceOf(address _owner) public view returns (uint256 balance)",
  "event Approval(address indexed _owner, address indexed _spender, uint256 _value)",
];

export const Erc20Interface = new ethers.Interface(Erc20);

export const encodeTransfer = (
  target: string,
  amount: string | number,
): string => {
  return Erc20Interface.encodeFunctionData("transfer", [target, amount]);
};

export const encodeTransferFrom = (
  from: string,
  target: string,
  amount: string | number,
): string => {
  return Erc20Interface.encodeFunctionData("transferFrom", [
    from,
    target,
    amount,
  ]);
};

// rethrow "cleaned up" exception.
// - stack trace goes back to method (or catch) line, not inner provider
// - attempt to parse revert data (needed for geth)
// use with ".catch(rethrow())", so that current source file/line is meaningful.
export function rethrow(): (e: Error) => void {
  const callerStack = new Error()
    .stack!.replace(/Error.*\n.*at.*\n/, "")
    .replace(/.*at.* \(internal[\s\S]*/, "");

  if (arguments[0] != null) {
    throw new Error("must use .catch(rethrow()), and NOT .catch(rethrow)");
  }
  return function (e: Error) {
    const solstack = e.stack!.match(/((?:.* at .*\.sol.*\n)+)/);
    const stack = (solstack != null ? solstack[1] : "") + callerStack;
    // const regex = new RegExp('error=.*"data":"(.*?)"').compile()
    const found = /error=.*?"data":"(.*?)"/.exec(e.message);
    let message: string;
    if (found != null) {
      const data = found[1];
      message =
        decodeRevertReason(data) ?? e.message + " - " + data.slice(0, 100);
    } else {
      message = e.message;
    }
    const err = new Error(message);
    err.stack = "Error: " + message + "\n" + stack;
    throw err;
  };
}

const decodeRevertReasonContracts = new Interface([
  ...EntryPoint__factory.createInterface().fragments,
  "error ECDSAInvalidSignature()",
]); // .filter(f => f.type === 'error'))

export function decodeRevertReason(
  data: string | Error,
  nullIfNoMatch = true,
): string | null {
  if (typeof data !== "string") {
    const err = data as any;
    data = (err.data ?? err.error?.data) as string;
    if (typeof data !== "string") throw err;
  }

  const methodSig = data.slice(0, 10);
  const dataParams = "0x" + data.slice(10);

  // can't add Error(string) to xface...
  if (methodSig === "0x08c379a0") {
    const [err] = coder.decode(["string"], dataParams);
    // eslint-disable-next-line @typescript-eslint/restrict-template-expressions
    return `Error(${err})`;
  } else if (methodSig === "0x4e487b71") {
    const [code] = coder.decode(["uint256"], dataParams);
    return `Panic(${panicCodes[code] ?? code} + ')`;
  }

  try {
    const err = decodeRevertReasonContracts.parseError(data);
    // treat any error "bytes" argument as possible error to decode (e.g. FailedOpWithRevert, PostOpReverted)
    const args = err!.args.map((arg: any, index) => {
      switch (err?.fragment.inputs[index].type) {
        case "bytes":
          return decodeRevertReason(arg);
        case "string":
          return `"${arg as string}"`;
        default:
          return arg;
      }
    });
    return `${err!.name}(${args.join(",")})`;
  } catch (e) {
    // throw new Error('unsupported errorSig ' + data)
    if (!nullIfNoMatch) {
      return data;
    }
    return null;
  }
}

export function tonumber(x: any): number {
  try {
    return parseFloat(x.toString());
  } catch (e: any) {
    console.log("=== failed to parseFloat:", x, e.message);
    return NaN;
  }
}

// just throw 1eth from account[0] to the given address (or contract instance)
export async function fund(
  contractOrAddress: string | Contract,
  amountEth = "1",
): Promise<void> {
  let address: string;
  if (typeof contractOrAddress === "string") {
    address = contractOrAddress;
  } else {
    address = await contractOrAddress.getAddress();
  }
  const [firstSigner] = await ethers.getSigners();
  await firstSigner.sendTransaction({
    to: address,
    value: parseEther(amountEth),
  });
}

export async function getBalance(address: string): Promise<number> {
  const balance = await ethers.provider.getBalance(address);
  return parseInt(balance.toString());
}

export async function getTokenBalance(
  token: IERC20,
  address: string,
): Promise<number> {
  const balance = await token.balanceOf(address);
  return parseInt(balance.toString());
}

export async function isDeployed(addr: string): Promise<boolean> {
  const code = await ethers.provider.getCode(addr);
  return code.length > 2;
}

// Getting initcode for AccountFactory which accepts one validator (with ECDSA owner required for installation)
export async function getInitCode(
  ownerAddress: AddressLike,
  factoryAddress: AddressLike,
  validatorAddress: AddressLike,
  saDeploymentIndex: number = 0,
): Promise<string> {
  const AccountFactory = await ethers.getContractFactory("AccountFactory");
  const moduleInstallData = ethers.solidityPacked(["address"], [ownerAddress]);

  // Encode the createAccount function call with the provided parameters
  const factoryDeploymentData = AccountFactory.interface
    .encodeFunctionData("createAccount", [
      validatorAddress,
      moduleInstallData,
      saDeploymentIndex,
    ])
    .slice(2);

  return factoryAddress + factoryDeploymentData;
}

export function callDataCost(data: string): number {
  return ethers
    .getBytes(data)
    .map((x) => (x === 0 ? 4 : 16))
    .reduce((sum, x) => sum + x);
}

export function parseValidationData(
  validationData: BigNumberish,
): ValidationData {
  const data = ethers.zeroPadValue(toBeHex(validationData), 32);

  // string offsets start from left (msb)
  const aggregator = dataSlice(data, 32 - 20);
  let validUntil = parseInt(dataSlice(data, 32 - 26, 32 - 20));
  if (validUntil === 0) {
    validUntil = maxUint48;
  }
  const validAfter = parseInt(dataSlice(data, 0, 6));

  return {
    aggregator,
    validAfter,
    validUntil,
  };
}
