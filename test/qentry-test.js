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

beforeEach(async () => {
  [owner, addr1, addr2, burnaddr, ...addrs] = await ethers.getSigners();
  QEntry = await ethers.getContractFactory("QEntry");
  qentToken = await QEntry.deploy();
});

describe("Deployment", async function () {
  it("Should set the right owner", async function () {
    expect(await qentToken.owner()).to.equal(owner.address);
  });

  it("Should mint 1000 token to owner", async function () {
    const balance = await qentToken.balanceOf(owner.address);
    expect(await qentToken.totalSupply()).to.equal(balance);
  });
});

describe("Transaction", async function () {
  it("Should transfer tokens between account", async function () {
    await qentToken.transfer(addr1.address, 500);
    const balance = await qentToken.balanceOf(addr1.address);
    expect(balance).to.equal(500);
  });

  it("Should allow approval", async function () {
    await qentToken.transfer(addr1.address, ethers.utils.parseEther("50"));
    await qentToken
      .connect(addr1)
      .approve(owner.address, ethers.utils.parseEther("50"));
    await qentToken.transferFrom(
      addr1.address,
      addr2.address,
      ethers.utils.parseEther("50")
    );
    expect(await qentToken.balanceOf(addr2.address)).to.equal(
      ethers.utils.parseEther("50")
    );
  });

  it("should transfer ownership", async function () {
    await qentToken.transferOwnership(addr1.address);
    expect(await qentToken.owner()).to.equal(addr1.address);
  });
});
