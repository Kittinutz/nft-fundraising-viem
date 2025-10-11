import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";

import { network } from "hardhat";
import { formatEther } from "ox/Value";

describe("FundRaisingContractNFT", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const [wallet1, wallet2] = await viem.getWalletClients();
  let fundContractNFT: any, nftContract: any, usdtContract: any;
  beforeEach(async function () {
    const nft = await viem.deployContract("DZNFT", []);
    nftContract = nft;
    const usdt = await viem.deployContract("MockUSDT", [
      "Mock USDT",
      "MUSDT",
      18n,
      1000000000n * 10n ** 18n,
    ]);
    usdtContract = usdt;
    const fundRaisingContract = await viem.deployContract(
      "FundRaisingContractNFT",
      [nftContract.address, usdtContract.address]
    );
    await nft.write.updateExecutorRole([fundRaisingContract.address, true]);
    fundContractNFT = fundRaisingContract;
  });

  it("Owner DZNFT contract Should be owner", async function () {
    const nft = await viem.getContractAt("DZNFT", nftContract?.address);
    assert.equal(
      (await nft.read.owner()).toLowerCase(),
      wallet1.account.address
    );
  });
  it("Fund Contract Should be executor", async function () {
    const nft = await viem.getContractAt("DZNFT", nftContract?.address);
    assert.equal(
      await nft.read.hasRole([
        await nft.read.EXECUTOR_ROLE(),
        fundContractNFT.address,
      ]),
      true
    );
  });
  it("Mint USDT to Wallet should be success", async function () {
    const usdt = await viem.getContractAt("MockUSDT", usdtContract?.address);
    await usdt.write.mint([wallet2.account.address, 1000000000n * 10n ** 18n]);
    assert.equal(
      await usdt.read.balanceOf([wallet2.account.address]),
      1000000000n * 10n ** 18n
    );
  });
  it("Owner create Round should be success", async function () {
    const fundContract = await viem.getContractAt(
      "FundRaisingContractNFT",
      fundContractNFT?.address
    );
    await fundContract.write.createInvestmentRound([
      "Round 1",
      500n * 10n ** 18n,
      6n,
      1000n,
      (Date.now() + 1000000) * 1000,
      (Date.now() + 10000000) * 1000,
    ]);
    const round = await fundContract.read.investmentRounds([0n]);
    assert.equal(round[0], 0n);
    assert.equal(round[1], "Round 1");
    assert.equal(formatEther(round[2]), "500");
  });
});
