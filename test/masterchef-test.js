const { expect } = require("chai");
const { ethers } = require("hardhat");

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
let provider;

beforeEach(async () => {
  [owner, addr1, addr2, burnaddr, ...addrs] = await ethers.getSigners();
  QEntry = await ethers.getContractFactory("QEntry");
  qentToken = await QEntry.deploy();
  provider = await ethers.getDefaultProvider();
  Masterchef = await ethers.getContractFactory("MasterChef");
  masterchef = await Masterchef.deploy(
    qentToken.address,
    burnaddr.address,
    addr1.address,
    ethers.utils.parseEther("100"),
    13445720
  );
  await qentToken.transferOwnership(masterchef.address);
});
describe("Masterchef Property", async function () {
  it("should have the right emission rate", async function () {
    const qentryPerBlock = await masterchef.QentryPerBlock();
    expect(qentryPerBlock).to.equal(ethers.utils.parseEther("100"));
  });
});

describe("Adding Pool Masterchef", async function () {
  beforeEach(async () => {
    await masterchef.addPool(100, qentToken.address, 1000, false);
  });
  it("should allows adding a new pool", async function () {
    expect(await masterchef.poolLength()).to.equal(1);
  });
  it("should not allow duplicate pool", async function () {
    await expect(
      masterchef.addPool(100, qentToken.address, 1000, false)
    ).to.be.revertedWith("nonDuplicated: duplicated");
  });
  it("pool should have the right lp token", async function () {
    const poolInfo = await masterchef.poolInfo(0);
    expect(poolInfo[0]).to.equal(qentToken.address);
  });
});

describe("Deposit in Pool Masterchef", async function () {
  beforeEach(async function () {
    await masterchef.addPool(100, qentToken.address, 1000, false);
    await qentToken.approve(masterchef.address, ethers.utils.parseEther("100"));
    await masterchef.deposit(0, ethers.utils.parseEther("50"));
  });
  it("should emit deposit event once deposit", async function () {
    await expect(masterchef.deposit(0, ethers.utils.parseEther("50")))
      .to.emit(masterchef, "Deposit")
      .withArgs(owner.address, 0, ethers.utils.parseEther("50"));
  });
  it("should show corrected deposit amount", async function () {
    const amount = await masterchef.userInfo(0, owner.address);
    expect(amount.amount).to.equal(ethers.utils.parseEther("45"));
  });
  it("should advance block", async function () {
    const currentBlock = await ethers.provider.getBlockNumber();
    await ethers.provider.send("evm_mine");
    const nextBlock = await ethers.provider.getBlockNumber();
    expect(currentBlock + 1).to.equal(nextBlock);
  });
  it("should send fee to fee address", async function () {
    const balance = await qentToken.balanceOf(addr1.address);
    expect(balance).to.equal(ethers.utils.parseEther("5"));
  });
});

describe("Reward and harvest Masterchef", async function () {
  beforeEach(async function () {
    await masterchef.addPool(100, qentToken.address, 1000, false);
    await qentToken.approve(masterchef.address, ethers.utils.parseEther("100"));
    await masterchef.deposit(0, ethers.utils.parseEther("50"));
    await ethers.provider.send("evm_mine");
    await ethers.provider.send("evm_mine");
    await ethers.provider.send("evm_mine");
    await ethers.provider.send("evm_mine");
    await ethers.provider.send("evm_mine");
  });
  it("should have pending reward balance", async function () {
    const pendingReward = ethers.utils.formatEther(
      await masterchef.pendingQentry(0, owner.address)
    );
    expect(parseInt(pendingReward)).to.be.within(499, 500);
  });
  it("should allow harvest", async function () {
    const initialBalance = await qentToken.balanceOf(owner.address);
    await masterchef.harvest(0);
    const afterBalance = await qentToken.balanceOf(owner.address);
    expect(afterBalance).to.be.above(initialBalance);
  });
  it("should emit harvest event", async function () {
    expect(await masterchef.harvest(0)).to.emit(masterchef, "Harvest");
  });
});
