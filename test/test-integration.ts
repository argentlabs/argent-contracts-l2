import hre from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ArgentWallet, ArgentWallet__factory, EntryPoint, EntryPoint__factory, TestCounter, TestCounter__factory } from "../typechain";
import { AASigner, localUserOpSender, rpcUserOpSender, SendUserOp } from "../scripts/lib/AASigner";
import { objdump } from "../scripts/lib/testutils";
import { deployAll } from "../scripts/deploy";

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

  before(async () => {
    [deployer, signer, guardian, thirdParty] = await ethers.getSigners();
    console.log(`deployer ${deployer.address}`);
    console.log(`signer ${signer.address}`);
    console.log(`guardian ${guardian.address}`);
    ArgentWallet = await ethers.getContractFactory("ArgentWallet");
    selectors = Object.fromEntries(Object.keys(selectors).map((method) => [method, ArgentWallet.interface.getSighash(method)])) as any;


    let entryPointAddress, testCounterAddress;

    if (hre.network.name === "hardhat") {
      console.log(`deploying ArgentWallet`);
      ({ entryPoint, wallet, testCounter } = await deployAll({ from: deployer, signer: signer.address, guardian: guardian.address }));

      entryPointAddress = entryPoint.address;
      testCounterAddress = testCounter.address;
      // hre.run("deploy", { signerAddress: signer.address, guardianAddress: guardian.address });
      // wallet = await ArgentWallet.deploy(...args);
      // await wallet.deployed();
    } else {
      entryPointAddress = "0xF63621e54F16eC6e4A732e44EaA7708935f259eF";
      testCounterAddress = "0x4B52ceEDE2e695CAeDBC1Cc8E7f9d5Ef18F0EeF5";
      wallet = ArgentWallet.attach("0x15A83ceCCBC597F4E882596f7aEe28793Ca23Ea3");
      // console.log(`verifying etherscan`);
      // const args = [signer.address, guardian.address, entryPointAddress] as const;
      // await hre.run("verify:verify", { address: wallet.address, constructorArguments: args });
    }
    console.log(`ArgentWallet at ${wallet.address}`)

    let sendUserOp: SendUserOp;
    if (hre.network.name === "hardhat") {
      console.log("using local")
      sendUserOp = localUserOpSender(entryPointAddress, deployer);
    } else {
      console.log("using rpc")
      sendUserOp = rpcUserOpSender(new ethers.providers.JsonRpcProvider(process.env.AA_URL));
    }

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
