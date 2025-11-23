import assert from "node:assert/strict";
import { beforeEach, describe, it } from "node:test";

import { network } from "hardhat";

describe("Debug Analytics", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const [wallet1] = await viem.getWalletClients();
  let fundRaisingCore: any,
    fundRaisingAnalytics: any,
    nftContract: any,
    usdtContract: any;

  beforeEach(async function () {
    // Deploy DZNFT
    const nft = await viem.deployContract("DZNFT", []);
    nftContract = nft;

    // Deploy MockUSDT
    const usdt = await viem.deployContract("MockUSDT", [
      "Mock USDT",
      "MUSDT",
      18,
      1000n * 10n ** 6n,
    ]);
    usdtContract = usdt;

    // Deploy Core Contract
    const coreContract = await viem.deployContract("FundRaisingCore", [
      nftContract.address,
      usdtContract.address,
    ]);
    fundRaisingCore = coreContract;

    // Deploy Analytics Contract
    const analyticsContract = await viem.deployContract(
      "FundRaisingAnalytics",
      [fundRaisingCore.address]
    );
    fundRaisingAnalytics = analyticsContract;

    // Grant executor role to core contract
    await nft.write.updateExecutorRole([fundRaisingCore.address, true]);
  });

  it("Should debug analytics contract response", async function () {
    // Get current timestamp
    const currentBlock = await publicClient.getBlock();
    const currentTime = Number(currentBlock.timestamp);

    console.log("Creating round...");
    await fundRaisingCore.write.createInvestmentRound([
      "Debug Test Round",
      500n,
      6n,
      1000n,
      BigInt(currentTime + 30 * 24 * 60 * 60),
      BigInt(currentTime + 365 * 24 * 60 * 60),
    ]);

    console.log("Getting round directly from core...");
    const coreRound = await fundRaisingCore.read.investmentRounds([0n]);
    console.log("Core round:", coreRound);

    console.log("Getting round from analytics...");
    try {
      const analyticsResponse =
        await fundRaisingAnalytics.read.getInvestmentRound([0n]);
      console.log("Analytics response:", analyticsResponse);
      console.log("Round data:", analyticsResponse[0]);
      console.log("Round name:", analyticsResponse[0]?.roundName);
    } catch (error) {
      console.error("Analytics error:", error);
    }

    console.log("Getting rounds count...");
    const roundsCount = await fundRaisingAnalytics.read.getRoundsCount();
    console.log("Rounds count:", roundsCount);
  });
});
