import hre from "hardhat";
import {Create2Factory} from "./lib/Create2Factory";
import {ethers} from "hardhat";

const PER_OP_OVERHEAD = 22000;
const UNSTAKE_DELAY_BLOCKS = 100;

export const deployAll = async function ({ signer, guardian }: any) {
  console.log(`deployAll`)
  const EntryPoint = await ethers.getContractFactory("EntryPoint");
  const entryPoint = await EntryPoint.deploy(Create2Factory.contractAddress, PER_OP_OVERHEAD, UNSTAKE_DELAY_BLOCKS, {
    gasLimit: 5e6,
  })
  console.log('==entrypoint addr=', entryPoint.address)

  const ArgentWallet = await ethers.getContractFactory("ArgentWallet");
  const wallet = await ArgentWallet.deploy(signer, guardian, entryPoint.address, {
    gasLimit: 5e6,
  })
  console.log('== wallet=', wallet.address)

  const TestCounter = await ethers.getContractFactory("TestCounter");
  const testCounter = await TestCounter.deploy({ gasLimit: 2e6 })

  console.log('==testCounter=', testCounter.address)

  return { 
    entryPointAddress: entryPoint.address,
    walletAddress: wallet.address,
    testCounterAddress: testCounter.address,
  };
}