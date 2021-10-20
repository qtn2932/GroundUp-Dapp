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
    100,
    13445720
  );
  await qentToken.transferOwnership(masterchef.address);
});

describe("Transactional Masterchef", async function () {
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
  it("should allow deposit", async function () {
    const poolInfo = await masterchef.poolInfo(0);
    expect(poolInfo[0]).to.equal(1);
  });
});
