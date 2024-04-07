import {
    AddressLike,
    BigNumberish,
    BytesLike,
  } from "ethers";

export interface UserOperation {
    sender: AddressLike; // Or string
    nonce?: BigNumberish;
    initCode?: BytesLike;
    callData?: BytesLike;
    callGasLimit?: BigNumberish;
    verificationGasLimit?: BigNumberish;
    preVerificationGas?: BigNumberish;
    maxFeePerGas?: BigNumberish;
    maxPriorityFeePerGas?: BigNumberish;
    paymaster?: AddressLike; // Or string
    paymasterVerificationGasLimit?: BigNumberish;
    paymasterPostOpGasLimit?: BigNumberish;
    paymasterData?: BytesLike;
    signature?: BytesLike;
  }

  export interface PackedUserOperation {
    sender: AddressLike; // Or string
    nonce: BigNumberish;
    initCode: BytesLike;
    callData: BytesLike;
    accountGasLimits: BytesLike;
    preVerificationGas: BigNumberish;
    gasFees: BytesLike;
    paymasterAndData: BytesLike;
    signature: BytesLike;
  }