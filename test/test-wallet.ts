import { BigNumber, BigNumberish } from "@ethersproject/bignumber";
import { BytesLike } from "@ethersproject/bytes";
import { ContractFactory } from "@ethersproject/contracts";
import { Wallet } from "@ethersproject/wallet";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ArgentWallet, Greeter } from "../typechain";

interface ISignedMessage {
  to?: string;
  selector: BytesLike;
  data: BytesLike;
  nonce?: BigNumberish;
}

describe("ArgentWallet", () => {
  const signer = ethers.Wallet.createRandom();
  const guardian = ethers.Wallet.createRandom();
  const thirdParty = ethers.Wallet.createRandom();

  let ArgentWallet: ContractFactory;
  let wallet: ArgentWallet;
  let selectors = {
    changeSigner: "",
    changeGuardian: "",
    triggerEscape: "",
    cancelEscape: "",
    escapeSigner: "",
    escapeGuardian: "",
  };

  const getSignatures = async (signers: Wallet[], { to, selector, data, nonce }: ISignedMessage) => {
    if (typeof to === "undefined") {
      to = wallet.address;
    }
    if (typeof nonce === "undefined") {
      nonce = await wallet.nonce();
    }
    const messageHex = await wallet.getSignedMessage(to, selector, data, nonce);
    const messageBytes = ethers.utils.arrayify(messageHex);
    const signatures = signers.map((signer) => signer.signMessage(messageBytes))
    return Promise.all(signatures);
  }

  before(async () => {
    ArgentWallet = await ethers.getContractFactory("ArgentWallet");
    selectors = Object.fromEntries(Object.keys(selectors).map((method) => [method, ArgentWallet.interface.getSighash(method)])) as any;
  });

  beforeEach(async () => {
    wallet = await ArgentWallet.deploy(signer.address, guardian.address) as ArgentWallet;
    await wallet.deployed();
  });

  it("should be in initial state", async () => {
    expect(await wallet.nonce()).to.equal(0);
    expect(await wallet.escape()).to.deep.equal([BigNumber.from(0), ethers.constants.AddressZero]);
  });

  it("should execute a transaction", async () => {
    const GreeterContract = await ethers.getContractFactory("Greeter");
    const greeter = await GreeterContract.deploy("Hello") as Greeter;

    const to = greeter.address;
    const calldata = greeter.interface.encodeFunctionData("setGreeting", ["Hola"]);
    const selector = calldata.slice(0, 10);
    const data = `0x${calldata.slice(10)}`;

    const [signerSignature, guardianSignature, thirdPartySignature] = await getSignatures(
      [signer, guardian, thirdParty],
      { to, selector, data }
    );

    // failures cases
    await expect(wallet.execute(ethers.constants.AddressZero, calldata, signerSignature, guardianSignature, 0)).to.be.revertedWith("null _to");
    await expect(wallet.execute(to, calldata, signerSignature, guardianSignature, 1)).to.be.revertedWith("invalid nonce");
    await expect(wallet.execute(to, calldata, signerSignature, thirdPartySignature, 0)).to.be.revertedWith("invalid signature");
    await expect(wallet.execute(to, calldata, thirdPartySignature, guardianSignature, 0)).to.be.revertedWith("invalid signature");
    await expect(wallet.execute(to, calldata, "0x", "0x", 0)).to.be.revertedWith("invalid signature");

    // success case
    expect(await greeter.greet()).to.equal("Hello");
    await wallet.execute(to, calldata, signerSignature, guardianSignature, 0);
    expect(await greeter.greet()).to.equal("Hola");
    expect(await wallet.nonce()).to.equal(1);
  });

  it("should change signer", async () => {
    const newSigner = ethers.Wallet.createRandom();

    const [signerSignature, guardianSignature, thirdPartySignature] = await getSignatures(
      [signer, guardian, thirdParty],
      { selector: selectors.changeSigner, data: newSigner.address },
    );

    // failures cases
    await expect(wallet.changeSigner(ethers.constants.AddressZero, signerSignature, guardianSignature, 0)).to.be.revertedWith("null _newSigner");
    await expect(wallet.changeSigner(newSigner.address, signerSignature, guardianSignature, 1)).to.be.revertedWith("invalid nonce");
    await expect(wallet.changeSigner(newSigner.address, signerSignature, thirdPartySignature, 0)).to.be.revertedWith("invalid signature");

    // success case
    expect(await wallet.callStatic["signer"]()).to.equal(signer.address);
    await expect(wallet.changeSigner(newSigner.address, signerSignature, guardianSignature, 0)).to.not.be.reverted;
    expect(await wallet.callStatic["signer"]()).to.equal(newSigner.address);
    expect(await wallet.nonce()).to.equal(1);
  });

  it("should change guardian", async () => {
    const newGuardian = ethers.Wallet.createRandom();

    const [signerSignature, guardianSignature, thirdPartySignature] = await getSignatures(
      [signer, guardian, thirdParty],
      { selector: selectors.changeGuardian, data: newGuardian.address },
    );

    // failures cases
    await expect(wallet.changeSigner(ethers.constants.AddressZero, signerSignature, guardianSignature, 0)).to.be.revertedWith("null _newSigner");
    await expect(wallet.changeSigner(newGuardian.address, signerSignature, guardianSignature, 1)).to.be.revertedWith("invalid nonce");
    await expect(wallet.changeSigner(newGuardian.address, signerSignature, thirdPartySignature, 0)).to.be.revertedWith("invalid signature");

    // success case
    expect(await wallet.guardian()).to.equal(guardian.address);
    await wallet.changeGuardian(newGuardian.address, signerSignature, guardianSignature, 0);
    expect(await wallet.guardian()).to.equal(newGuardian.address);
    expect(await wallet.nonce()).to.equal(1);
  });

  it("should trigger signer escape", async () => {
    const [signerSignature, guardianSignature, thirdPartySignature] = await getSignatures(
      [signer, guardian, thirdParty],
      { selector: selectors.triggerEscape, data: signer.address },
    );

    // failures cases
    await expect(wallet.triggerEscape(signer.address, guardianSignature, 0)).to.be.revertedWith("invalid signature");
    await expect(wallet.triggerEscape(signer.address, thirdPartySignature, 0)).to.be.revertedWith("invalid signature");

    const { timestamp } = await ethers.provider.getBlock(ethers.provider.getBlockNumber());

    await wallet.triggerEscape(signer.address, signerSignature, 0);
    const escapeSecurityPeriod = await wallet.ESCAPE_SECURITY_PERIOD();
    const [escapeAt, caller] = await wallet.escape();
    expect(escapeAt.gte(escapeSecurityPeriod.add(timestamp))).to.be.true;
    expect(caller).to.equal(signer.address);
  });

  // TODO: trigger guardian escape

  it("should cancel signer escape", async () => {
    let signerSignature, guardianSignature;

    [signerSignature] = await getSignatures([signer], { selector: selectors.triggerEscape, data: signer.address });
    await wallet.triggerEscape(signer.address, signerSignature, 0);

    [signerSignature, guardianSignature] = await getSignatures(
      [signer, guardian], 
      { selector: selectors.cancelEscape, data: "0x" }
    );
    await wallet.cancelEscape(signerSignature, guardianSignature, 1);
  });

  it("should escape signer", async () => {
    const newSigner = ethers.Wallet.createRandom();
    let guardianSignature;

    [guardianSignature] = await getSignatures([guardian], { selector: selectors.triggerEscape, data: guardian.address });
    await wallet.triggerEscape(guardian.address, guardianSignature, 0);

    // advance time
    const [escapeAt] = await wallet.escape();
    await ethers.provider.send("evm_setNextBlockTimestamp", [escapeAt.toNumber()]); 
    await ethers.provider.send("evm_mine", []);

    // success case
    [guardianSignature] = await getSignatures([guardian], { selector: selectors.escapeSigner, data: newSigner.address });
    await wallet.escapeSigner(newSigner.address, guardianSignature, 1);
    expect(await wallet.callStatic["signer"]()).to.equal(newSigner.address);
    expect(await wallet.escape()).to.deep.equal([BigNumber.from(0), ethers.constants.AddressZero]);
  });

  // TODO: escape guardian

});
