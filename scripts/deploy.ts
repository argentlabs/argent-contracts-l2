import hre from "hardhat";
import {Create2Factory} from "./lib/Create2Factory";
import {ethers} from "hardhat";

const PER_OP_OVERHEAD = 22000;
const UNSTAKE_DELAY_BLOCKS = 100;


export const deployArgentWallet = async function ({ signer, guardian, entryPoint }: any) {
  const args = [signer, guardian, entryPoint] as const;

  const ArgentWallet = await ethers.getContractFactory("ArgentWallet");
  const wallet = await ArgentWallet.deploy(...args, { gasLimit: 5e6 })
  console.log('== wallet=', wallet.address)


  if (hre.network.name !== "hardhat") {
    console.log("waiting for deployment");
    // await wallet.deployTransaction.wait(3);
    await wallet.deployed();
    console.log("Uploading code to Etherscan...");
    await hre.run("verify:verify", { address: wallet.address, constructorArguments: args });
  }

  return wallet.address;
}

export const deployAll = async function ({ signer, guardian }: any) {
  console.log(`deployAll`)
  const EntryPoint = await ethers.getContractFactory("EntryPoint");
  const entryPoint = await EntryPoint.deploy(Create2Factory.contractAddress, PER_OP_OVERHEAD, UNSTAKE_DELAY_BLOCKS, {
    gasLimit: 5e6,
  })
  console.log('==entrypoint addr=', entryPoint.address)

  const TestCounter = await ethers.getContractFactory("TestCounter");
  const testCounter = await TestCounter.deploy({ gasLimit: 2e6 })

  console.log('==testCounter=', testCounter.address)

  return { 
    entryPointAddress: entryPoint.address,
    walletAddress: await deployArgentWallet({ signer, guardian, entryPoint: entryPoint.address }),
    testCounterAddress: testCounter.address,
  };
}