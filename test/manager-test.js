const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  delay,
} = require("@nomiclabs/hardhat-etherscan/dist/src/etherscan/EtherscanService");

// configuring variable

let QEntry;
let qentToken;
let owner;
let addr1;
let addr2;
let burnaddr;
let addrs;
let Masterchef;
let masterchef;
let Manager;
let manager;
let provider;

beforeEach(async () => {
  [owner, addr1, addr2, burnaddr, ...addrs] = await ethers.getSigners();
  QEntry = await ethers.getContractFactory("QEntry");
  qentToken = await QEntry.deploy();
  provider = await ethers.getDefaultProvider();
  Manager = await ethers.getContractFactory("Manager");
  manager = await Manager.deploy();
  await manager.setQEntry(qentToken.address);
  Masterchef = await ethers.getContractFactory("MasterChef");
  masterchef = await Masterchef.deploy(
    qentToken.address,
    burnaddr.address,
    manager.address,
    ethers.utils.parseEther("100"),
    13445720
  );

  await qentToken.transferOwnership(masterchef.address);
  await manager.setBuyBackAddress(owner.address);
  await masterchef.addPool(100, qentToken.address, 1000, false);
  await qentToken.approve(masterchef.address, ethers.utils.parseEther("1000"));
  await masterchef.deposit(0, ethers.utils.parseEther("700"));
});

describe("Manager balance", async function () {
  it("Should receive correct funding", async function () {
    const balance = await qentToken.balanceOf(manager.address);
    expect(ethers.utils.formatEther(balance)).to.equal("70.0");
  });
});

describe("Manager prize pool", async function () {
  beforeEach(async () => {
    await qentToken.approve(manager.address, ethers.utils.parseEther("1000"));
    await manager.createPool(
      qentToken.address,
      ethers.utils.parseEther("70"),
      15
    );
  });
  it("should allows pool creation", async function () {
    expect(await manager.poolLength()).to.equal(1);
  });
  it("should allows entry", async function () {
    const sleep = (ms) => {
      return new Promise((resolve) => setTimeout(resolve, ms));
    };
    await sleep(15000);
    expect(await manager.enter(0)).to.emit(manager, "Entered");
  });
  it("should deduct the right amount of qentry", async function () {
    const sleep = (ms) => {
      return new Promise((resolve) => setTimeout(resolve, ms));
    };
    await sleep(15000);
    await manager.enter(0);
    const balance = await qentToken.balanceOf(owner.address);
    expect(ethers.utils.formatEther(balance)).to.equal("299.3");
  });
  it("should prevent entry after times up", async function () {});
});
