import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";

import { network } from "hardhat";
import { formatEther } from "ox/Value";
import dayjs from "dayjs";
import { parseEther } from "viem";

describe("FundRaising Split Architecture - Complete Test Suite", async function () {
  const { viem, networkHelpers } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const [wallet1, wallet2, wallet3] = await viem.getWalletClients();
  let fundRaisingCore: any,
    fundRaisingAnalytics: any,
    fundRaisingAdmin: any,
    fundRaisingClaims: any,
    nftContract: any,
    usdtContract: any;

  // Helper function to get current blockchain timestamp
  async function getCurrentTimestamp(): Promise<number> {
    const currentBlock = await publicClient.getBlock();
    return Number(currentBlock.timestamp);
  }

  // Helper function to get rounds in reverse chronological order (last created first)
  async function getRoundsReversed(
    analyticsContract: any,
    offset = 0,
    limit?: number
  ) {
    const [totalRounds] = await analyticsContract.read.getRoundsCount();
    const totalCount = Number(totalRounds);

    if (totalCount === 0) return [];

    // Calculate pagination bounds for reverse order
    const start = Math.max(totalCount - 1 - offset, 0);
    const actualLimit = limit ? Math.min(limit, start + 1) : start + 1;
    const end = Math.max(start - actualLimit + 1, 0);

    const rounds = [];
    for (let i = start; i >= end; i--) {
      const [round, enableClaimReward] =
        await analyticsContract.read.getInvestmentRound([BigInt(i)]);
      rounds.push({
        roundId: Number(round.roundId),
        roundName: round.roundName,
        tokenPrice: round.tokenPrice,
        rewardPercentage: Number(round.rewardPercentage),
        totalTokens: Number(round.totalTokenOpenInvestment),
        tokensSold: Number(round.tokensSold),
        closeDate: Number(round.closeDateInvestment),
        endDate: Number(round.endDateInvestment),
        isActive: round.isActive,
        exists: round.exists,
        createdAt: Number(round.createdAt),
        status: Number(round.status),
        enableClaimReward: enableClaimReward,
      });
    }

    return rounds;
  }

  beforeEach(async function () {
    // Deploy DZNFT
    const nft = await viem.deployContract("DZNFT", []);
    nftContract = nft;

    // Deploy MockUSDT
    const usdt = await viem.deployContract("MockUSDT", [
      "Mock USDT",
      "MUSDT",
      18,
      1000n * 10n ** 18n,
    ]);
    usdtContract = usdt;

    // Deploy Core Contract
    const coreContract = await viem.deployContract("FundRaisingCore", [
      nftContract.address,
      usdtContract.address,
    ]);
    fundRaisingCore = coreContract;

    // Deploy Claims Contract
    const claimsContract = await viem.deployContract("FundRaisingClaims", [
      fundRaisingCore.address,
      nftContract.address,
      usdtContract.address,
    ]);
    fundRaisingClaims = claimsContract;

    // Deploy Analytics Contract
    const analyticsContract = await viem.deployContract(
      "FundRaisingAnalytics",
      [fundRaisingCore.address]
    );
    fundRaisingAnalytics = analyticsContract;

    // Deploy Admin Contract
    const adminContract = await viem.deployContract("FundRaisingAdmin", [
      fundRaisingCore.address,
    ]);
    fundRaisingAdmin = adminContract;

    // Grant executor role to core contract
    await nft.write.updateExecutorRole([fundRaisingCore.address, true]);

    // Grant executor role to claims contract for marking rewards as claimed
    await nft.write.updateExecutorRole([fundRaisingClaims.address, true]);

    // Set the authorized claims contract address for security
    await fundRaisingCore.write.setAuthorizedClaimsContract([
      fundRaisingClaims.address,
    ]);
  });
  describe("Claim Reward By Date", function () {
    it("Should allow user to claim rewards based on date phases", async function () {
      const coreContractW2 = await viem.getContractAt(
        "FundRaisingCore",
        fundRaisingCore?.address,
        {
          client: { wallet: wallet2 },
        }
      );

      const claimsContractW2 = await viem.getContractAt(
        "FundRaisingClaims",
        fundRaisingClaims?.address,
        {
          client: { wallet: wallet2 },
        }
      );

      const usdt = await viem.getContractAt("MockUSDT", usdtContract?.address);
      const usdtW2 = await viem.getContractAt(
        "MockUSDT",
        usdtContract?.address,
        {
          client: { wallet: wallet2 },
        }
      );

      // Mint USDT to wallet2
      await usdt.write.mint([wallet2.account.address, 1000n * 10n ** 18n]);

      const currentTime = await getCurrentTimestamp();

      await fundRaisingCore.write.createInvestmentRound([
        "Round 1",
        500n * 10n ** 18n, // 500 USDT per token (in wei)
        6n,
        1000n,
        BigInt(currentTime + 30 * 24 * 60 * 60),
        BigInt(currentTime + 365 * 24 * 60 * 60),
      ]);

      // Approve and invest
      await usdtW2.write.approve([fundRaisingCore.address, 1000n * 10n ** 18n]);
      await coreContractW2.write.investInRound([0n, 2n]);

      const balanceOfW2 = await usdt.read.balanceOf([wallet2.account.address]);
      // Handle very small precision errors - balance should be close to zero but may have tiny dust amounts
      const balanceEther = Number(formatEther(balanceOfW2));
      assert(
        balanceEther === 0,
        `Balance should be near zero, got ${balanceEther}`
      );

      const round = await fundRaisingCore.read.investmentRounds([0n]);
      assert.equal(round[5], 2n);

      const nftBalance = await nftContract.read.balanceOf([
        wallet2.account.address,
      ]);
      assert.equal(nftBalance, 2n);

      // Owner withdraws fund
      const ownerUsdt1 = await usdt.read.balanceOf([wallet1.account.address]);
      const ownerBalance1 = Number(formatEther(ownerUsdt1));
      assert(ownerBalance1 == 1000, `Expected ~1000, got ${ownerBalance1}`);

      await fundRaisingCore.write.withdrawFund([0n]);

      const ownerUsdt = await usdt.read.balanceOf([wallet1.account.address]);
      const ownerBalance = Number(formatEther(ownerUsdt));

      assert(
        ownerBalance == 2000,
        `Expected ~2000, after withdrawfund got ${ownerBalance}`
      );

      // Add rewards for claiming
      const beforeClaimW2Balance = await usdt.read.balanceOf([
        wallet2.account.address,
      ]);
      assert(
        Number(formatEther(beforeClaimW2Balance)) === 0,
        "Balance should be near zero"
      );

      await usdt.write.mint([wallet1.account.address, 30n * 10n ** 18n]);
      await usdt.write.approve([fundRaisingCore.address, 30n * 10n ** 18n]);
      await fundRaisingCore.write.addRewardToRound([0n, 30n]);

      const fundContractBalance = await usdt.read.balanceOf([
        fundRaisingCore.address,
      ]);
      assert.equal(formatEther(fundContractBalance), "30");

      // Fast forward time 7 months (210+ days after closeDate for 180+ day phase)
      await networkHelpers.mine();
      await networkHelpers.time.increase(60 * 60 * 24 * 30 * 7);
      await networkHelpers.mine();

      // Claim reward (Phase 1: 50% reward)
      // Reward: 2 tokens * 500 USDT * 6% = 60 USDT, 50% = 30 USDT
      await claimsContractW2.write.claimRewardRound([0n]);

      const afterClaimW2Balance = await usdt.read.balanceOf([
        wallet2.account.address,
      ]);

      // Phase 1: Should receive 30 USDT (50% of reward)
      assert(
        Number(formatEther(afterClaimW2Balance)) === 30,
        `Should receive 30 USDT reward at 180 days, got ${formatEther(
          afterClaimW2Balance
        )}`
      );
      await usdt.write.mint([wallet1.account.address, 1030n * 10n ** 18n]);
      await usdt.write.approve([fundRaisingCore.address, 1030n * 10n ** 18n]);
      await fundRaisingCore.write.addRewardToRound([0n, 1030n]);
      await networkHelpers.mine();
      await networkHelpers.time.increase(60 * 60 * 24 * 30 * 7);
      await networkHelpers.mine();
      // Claim reward (Phase 1: 50% reward)
      // Reward: 2 tokens * 500 USDT * 6% = 60 USDT, 50% = 30 USDT
      await claimsContractW2.write.claimRewardRound([0n]);

      const afterClaimW2Balance2 = await usdt.read.balanceOf([
        wallet2.account.address,
      ]);

      // Phase 1: Should receive 30 USDT (50% of reward)
      assert(
        Number(formatEther(afterClaimW2Balance2)) === 1060,
        `Should receive 30 USDT reward at 180 days, got ${formatEther(
          afterClaimW2Balance2
        )}`
      );
    });
  });
});
