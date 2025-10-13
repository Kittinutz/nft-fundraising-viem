import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";

import { network } from "hardhat";
import { formatEther } from "ox/Value";
import dayjs from "dayjs";
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
      Date.now() + 30 * 24 * 60 * 60 * 1000,
      Date.now() + 365 * 24 * 60 * 60 * 1000,
    ]);
    const round = await fundContract.read.investmentRounds([0n]);
    assert.equal(round[0], 0n);
    assert.equal(round[1], "Round 1");
    assert.equal(formatEther(round[2]), "500");
    assert.equal(
      dayjs(Number(round[6])).format("YYYY-MM-DD"),
      dayjs().add(30, "day").format("YYYY-MM-DD")
    );
    assert.equal(
      dayjs(Number(round[7])).format("YYYY-MM-DD"),
      dayjs().add(365, "day").format("YYYY-MM-DD")
    );
  });
  it("Investor invest in Round should be success", async function () {
    const fundContract = await viem.getContractAt(
      "FundRaisingContractNFT",
      fundContractNFT?.address
    );
    const fundContractW2 = await viem.getContractAt(
      "FundRaisingContractNFT",
      fundContractNFT?.address,
      {
        client: { wallet: wallet2 },
      }
    );

    const usdt = await viem.getContractAt("MockUSDT", usdtContract?.address);
    const usdtW2 = await viem.getContractAt("MockUSDT", usdtContract?.address, {
      client: { wallet: wallet2 },
    });
    await fundContract.write.createInvestmentRound([
      "Round 1",
      500n * 10n ** 18n,
      6n,
      1000n,
      Date.now() + 30 * 24 * 60 * 60 * 1000,
      Date.now() + 365 * 24 * 60 * 60 * 1000,
    ]);
    await usdt.write.mint([wallet2.account.address, 1000000000n * 10n ** 18n]);
    await usdtW2.write.approve([
      fundContract.address,
      1000000000n * 10n ** 18n,
    ]);

    await fundContractW2.write.investInRound([0n, 2n]);

    const round = await fundContract.read.investmentRounds([0n]);
    assert.equal(round[4], 1000n);
    const nftBalance = await nftContract.read.balanceOf([
      wallet2.account.address,
    ]);
    assert.equal(nftBalance, 2n);
  });
});
