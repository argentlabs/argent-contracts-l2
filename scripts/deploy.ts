import { ethers } from "hardhat";

(async () => {
  try {
    // We get the contract to deploy
    const Greeter = await ethers.getContractFactory("Sandbox");
    const greeter = await Greeter.deploy();

    await greeter.deployed();
    await greeter.test();

    console.log("Greeter deployed to:", greeter.address);
  } catch (error) {
    console.error(error);
    process.exitCode = 1;
  }
})();
