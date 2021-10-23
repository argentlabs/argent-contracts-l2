import hre from "hardhat";
import { BigNumber, BigNumberish } from "@ethersproject/bignumber";
import { BytesLike } from "@ethersproject/bytes";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ArgentWallet, ArgentWallet__factory, EntryPoint, EntryPoint__factory, TestCounter, TestCounter__factory } from "../typechain";
import { AASigner, localUserOpSender, rpcUserOpSender, SendUserOp } from "../scripts/lib/AASigner";
import { objdump } from "../scripts/lib/testutils";

const entryPointAddress = "0xF63621e54F16eC6e4A732e44EaA7708935f259eF";
const testCounterAddress = "0x4B52ceEDE2e695CAeDBC1Cc8E7f9d5Ef18F0EeF5";
const sendUserOp = rpcUserOpSender(new ethers.providers.JsonRpcProvider(process.env.AA_URL));

describe("ArgentWallet", () => {
  let deployer: SignerWithAddress;
  let signer: SignerWithAddress;
  let guardian: SignerWithAddress;
  let thirdParty: SignerWithAddress;

  let ArgentWallet: ArgentWallet__factory;
  let wallet: ArgentWallet;
  let testCounter: TestCounter;
  let selectors = {
    changeSigner: "",
    changeGuardian: "",
    triggerEscape: "",
    cancelEscape: "",
    escapeSigner: "",
    escapeGuardian: "",
  };

  let currentStake = "";
  let entryPoint: EntryPoint;

  // const getSignatures = async (signers: Wallet[], { to, value = 0, data, nonce }: ISignedMessage) => {
  //   if (typeof to === "undefined") {
  //     to = wallet.address;
  //   }
  //   if (typeof nonce === "undefined") {
  //     nonce = await wallet.nonce();
  //   }
  //   const messageHex = await wallet.getSignedMessage(to, value, data, nonce);
  //   const messageBytes = ethers.utils.arrayify(messageHex);
  //   const promises = signers.map((signer) => signer.signMessage(messageBytes))
  //   const signatures = Promise.all(promises);
  //   console.log(`signatures ${signatures}`);
  //   return signatures;
  // }

  before(async () => {
    [deployer, signer, guardian, thirdParty] = await ethers.getSigners();
    console.log(`deployer ${deployer.address}`);
    console.log(`signer ${signer.address}`);
    console.log(`guardian ${guardian.address}`);
    ArgentWallet = await ethers.getContractFactory("ArgentWallet");
    selectors = Object.fromEntries(Object.keys(selectors).map((method) => [method, ArgentWallet.interface.getSighash(method)])) as any;

    // console.log(`deploying ArgentWallet`)
    const args = [signer.address, guardian.address, entryPointAddress] as const;
    // wallet = await ArgentWallet.deploy(...args);
    wallet = ArgentWallet.attach("0x15A83ceCCBC597F4E882596f7aEe28793Ca23Ea3");
    console.log(`verifying etherscan`)
    await hre.run("verify:verify", { address: wallet.address, constructorArguments: args });

    console.log(`deployed at ${wallet.address}`)
    await wallet.deployed();

    const aaSigner = new AASigner([signer, guardian], entryPointAddress, sendUserOp);
    console.log(`connecting wallet address`)
    await aaSigner.connectWalletAddress(wallet.address)
    if (await ethers.provider.getBalance(wallet.address) < ethers.utils.parseEther("0.01")) {
      console.log("prefund wallet")
      await deployer.sendTransaction({to: wallet.address, value: ethers.utils.parseEther("0.01")})
      console.log("funded")
    }

    //usually, a wallet will deposit for itself (that is, get created using eth, run "addDeposit" for itself
    // and from there on will use deposit
    // for testing,
    entryPoint = EntryPoint__factory.connect(entryPointAddress, deployer)
    const info = await entryPoint.getStakeInfo(wallet.address)
    currentStake = info.stake.toString()
    console.log("current stake=", currentStake)

    if (info.stake.lte(ethers.utils.parseEther("0.01"))) {
      console.log("depositing for wallet")
      entryPoint.addDepositTo(wallet.address, {value: ethers.utils.parseEther("0.01")})
    }

    testCounter = TestCounter__factory.connect(testCounterAddress, aaSigner)
  });

  beforeEach(async () => {
    // wallet = await ArgentWallet.deploy(signer.address, guardian.address, ethers.constants.AddressZero);
  });

  it("should execute a transaction with value", async () => {
    const prebalance = await ethers.provider.getBalance(wallet.address)
    console.log("current counter=", await testCounter.counters(wallet.address), "balance=", prebalance, "stake=", currentStake)
    const ret = await testCounter.count()
    console.log("waiting for mine, tmp.hash=", ret.hash)
    const receipt = await ret.wait()
    console.log("rcpt", receipt.transactionHash, `https://dashboard.tenderly.co/tx/goerli/${receipt.transactionHash}/gas-usage`)
    let gasPaid = prebalance.sub(await ethers.provider.getBalance(wallet.address))
    console.log("counter after=", await testCounter.counters(wallet.address), "paid=", gasPaid.toNumber() / 1e9, "gasUsed=", receipt.gasUsed)
    const logs = await entryPoint.queryFilter("*" as any, receipt.blockNumber)
    console.log(logs.map((e:any)=>({ev:e.event, ...objdump(e.args!)})))
  });

});
