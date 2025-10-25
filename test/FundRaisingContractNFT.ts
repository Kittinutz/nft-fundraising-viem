import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";

import { network } from "hardhat";
import { formatEther } from "ox/Value";
import dayjs from "dayjs";
import { parseEther } from "viem";
describe("FundRaisingContractNFT", async function () {
  const { viem, networkHelpers } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const [wallet1, wallet2, wallet3] = await viem.getWalletClients();
  let fundContractNFT: any, nftContract: any, usdtContract: any;

  // Helper function to get rounds in reverse chronological order (last created first)
  async function getRoundsReversed(contract: any, offset = 0, limit?: number) {
    const [totalRounds] = await contract.read.getRoundsCount();
    const totalCount = Number(totalRounds);

    if (totalCount === 0) return [];

    // Calculate pagination bounds for reverse order
    const start = Math.max(totalCount - 1 - offset, 0);
    const actualLimit = limit ? Math.min(limit, start + 1) : start + 1;
    const end = Math.max(start - actualLimit + 1, 0);

    const rounds = [];
    for (let i = start; i >= end; i--) {
      const round = await contract.read.investmentRounds([BigInt(i)]);
      rounds.push({
        roundId: Number(round[0]),
        roundName: round[1],
        tokenPrice: round[2],
        rewardPercentage: Number(round[3]),
        totalTokens: Number(round[4]),
        tokensSold: Number(round[5]),
        closeDate: Number(round[6]),
        endDate: Number(round[7]),
        isActive: round[8],
        exists: round[9],
        createdAt: Number(round[10]),
        status: Number(round[11]),
      });
    }

    return rounds;
  }
  beforeEach(async function () {
    const nft = await viem.deployContract("DZNFT", []);
    nftContract = nft;
    const usdt = await viem.deployContract("MockUSDT", [
      "Mock USDT",
      "MUSDT",
      18n,
      1000n * 10n ** 18n,
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
    const usdt = await viem.getContractAt("MockUSDT", usdtContract?.address);
    const balanceOf = await usdt.read.balanceOf([wallet1.account.address]);
    assert.equal(formatEther(balanceOf), "1000");
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

  it("Should test pagination with sorting after creating round", async function () {
    const contract = await viem.getContractAt(
      "FundRaisingContractNFT",
      fundContractNFT.address
    );

    // Create a test round
    const roundName = "Test Round 1";
    const tokenPrice = parseEther("10"); // 10 USDT per token
    const rewardPercentage = 1200n; // 12%
    const totalTokens = 1000n;
    const currentTime = Math.floor(Date.now() / 1000);
    const closeDate = BigInt(currentTime + 86400 * 30); // 30 days from now
    const endDate = BigInt(currentTime + 86400 * 365); // 1 year from now

    // Create the round
    await contract.write.createInvestmentRound([
      roundName,
      tokenPrice,
      rewardPercentage,
      totalTokens,
      closeDate,
      endDate,
    ]);

    // Get total rounds count for pagination
    const [totalRounds, activeRounds] = await contract.read.getRoundsCount();

    const offset = 0n;
    const limit = 10n;

    // Manual pagination implementation using available functions
    const startIndex = Number(offset);
    const endIndex = Math.min(startIndex + Number(limit), Number(totalRounds));
    const roundsToFetch = endIndex - startIndex;

    // Fetch round information for pagination range
    const rounds = [];
    const investorCounts = [];

    for (let i = startIndex; i < endIndex; i++) {
      // Get basic round data
      const round = await contract.read.investmentRounds([BigInt(i)]);

      // Get investors for this round

      rounds.push(round);
    }

    // Calculate pagination metadata
    const totalPages = Math.ceil(Number(totalRounds) / Number(limit));
    const currentPage = Math.floor(Number(offset) / Number(limit)) + 1;
    const hasMore = endIndex < Number(totalRounds);

    // Verify we got results
    assert.equal(rounds.length, 1); // should have 1 round
    assert.equal(rounds[0][1], roundName); // verify round name (index 1 is roundName)
    assert.equal(rounds[0][0], 0n); // verify round ID is 0 (index 0 is roundId)
    assert.equal(totalRounds, 1n); // verify total rounds
    assert.equal(totalPages, 1); // verify pagination calculation
    assert.equal(currentPage, 1); // verify current page
    assert.equal(hasMore, false); // verify hasMore flag
  });

  it("Mint USDT to Wallet should be success", async function () {
    const usdt = await viem.getContractAt("MockUSDT", usdtContract?.address);
    await usdt.write.mint([wallet2.account.address, 1000000000n * 10n ** 18n]);
    await usdt.write.transfer([wallet3.account.address, 1000n * 10n ** 18n]);
    const balanceOfW3 = await usdt.read.balanceOf([wallet3.account.address]);
    assert.equal(formatEther(balanceOfW3), "1000");
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
      500n,
      6n,
      1000n,
      BigInt(Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60),
      BigInt(Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60),
    ]);
    const round = await fundContract.read.investmentRounds([0n]);
    assert.equal(round[0], 0n);
    assert.equal(round[1], "Round 1");
    assert.equal(formatEther(round[2]), "500");
    // one month from now
    assert.equal(
      dayjs(Number(round[6]) * 1000).format("YYYY-MM-DD"),
      dayjs().add(30, "day").format("YYYY-MM-DD")
    );
    // one one year from now

    assert.equal(
      dayjs(Number(round[7]) * 1000).format("YYYY-MM-DD"),
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
      500n,
      6n,
      1000n,
      BigInt(Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60),
      BigInt(Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60),
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
  it("Owner withdraw fund and investor Redeem as  6, 12 month be success", async function () {
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
    //** mint w2 1000 usdt */
    await usdt.write.mint([wallet2.account.address, 1000n * 10n ** 18n]);

    const usdtW2 = await viem.getContractAt("MockUSDT", usdtContract?.address, {
      client: { wallet: wallet2 },
    });
    await fundContract.write.createInvestmentRound([
      "Round 1",
      500n,
      6n,
      1000n,
      BigInt(Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60),
      BigInt(Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60),
    ]);
    //** approve from w2 1000 usdt */

    await usdtW2.write.approve([fundContract.address, 1000n * 10n ** 18n]);
    /** invest 500*2 usdt */
    await fundContractW2.write.investInRound([0n, 2n]);
    const balanceOfW2 = await usdt.read.balanceOf([wallet2.account.address]);
    assert.equal(formatEther(balanceOfW2), "0");
    const round = await fundContract.read.investmentRounds([0n]);
    assert.equal(round[4], 1000n);
    const nftBalance = await nftContract.read.balanceOf([
      wallet2.account.address,
    ]);
    assert.equal(nftBalance, 2n);
    await fundContract.write.withdrawFund([0n]);
    const ownerUsdt = await usdt.read.balanceOf([wallet1.account.address]);
    assert.equal(formatEther(ownerUsdt), "2000");
    //** fast forward time 6 month */

    //** redeem nft 2 nft 1000 *6 % = 120/2 month = 60 */
    const beforeClaimW2Balance = await usdt.read.balanceOf([
      wallet2.account.address,
    ]);
    assert.equal(formatEther(beforeClaimW2Balance), "0");
    await usdt.write.mint([wallet1.account.address, 30n * 10n ** 18n]);
    await usdt.write.approve([fundContract.address, 30n * 10n ** 18n]);
    await fundContract.write.addRewardToRound([0n, 30n]);
    const fundContractBalace = await usdt.read.balanceOf([
      fundContract.address,
    ]);

    assert.equal(formatEther(fundContractBalace), "30");

    const block = await publicClient.getBlock();
    const currentRound = await fundContract.read.getInvestmentRound([0n]);
    await networkHelpers.mine();
    await networkHelpers.time.increase(60 * 60 * 24 * 30 * 7);
    await networkHelpers.mine();

    await fundContractW2.write.claimRewardRound([0n]);
    const afterClaimW2Balance = await usdt.read.balanceOf([
      wallet2.account.address,
    ]);
    assert.equal(formatEther(afterClaimW2Balance), "30");

    await usdt.write.mint([wallet1.account.address, 1030n * 10n ** 18n]);
    await usdt.write.approve([fundContract.address, 1030n * 10n ** 18n]);
    await fundContract.write.addRewardToRound([0n, 1030n]);
    const fundContractBalace2 = await usdt.read.balanceOf([
      fundContract.address,
    ]);

    assert.equal(formatEther(fundContractBalace2), "1030");
    await networkHelpers.mine();
    await networkHelpers.time.increase(60 * 60 * 24 * 30 * 10);
    await networkHelpers.mine();
    //** redeem nft 2 nft =  1000 * 6 % = 60 and 60 /2 = 30 + principle after complete one year with claim one*/

    await fundContractW2.write.claimRewardRound([0n]);
    const afterClaimW2Balance2 = await usdt.read.balanceOf([
      wallet2.account.address,
    ]);
    assert.equal(formatEther(afterClaimW2Balance2), "1060");
    const info = await fundContractW2.read.getInvestorDetail([
      wallet2.account.address,
    ]);
    //test getInvestorDetail
    assert.equal(info[3], 1060n * 10n ** 18n); //dividend claimed
    assert.equal(info[2], 1000n * 10n ** 18n); // total invest
    assert.equal(info[0], 2n);
    assert.deepEqual(info[1], [0n, 1n]); // token id
  });

  it("Owner withdraw fund and investor Redeem as  12 month be success", async function () {
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
    //** mint w2 1000 usdt */
    await usdt.write.mint([wallet2.account.address, 1000n * 10n ** 18n]);

    const usdtW2 = await viem.getContractAt("MockUSDT", usdtContract?.address, {
      client: { wallet: wallet2 },
    });
    const blockTimeStamp = await publicClient.getBlock();
    await fundContract.write.createInvestmentRound([
      "Round 1",
      500n,
      6n,
      1000n,
      BigInt(Number(blockTimeStamp.timestamp) + 30 * 24 * 60 * 60),
      BigInt(Number(blockTimeStamp.timestamp) + 365 * 24 * 60 * 60),
    ]);
    //** approve from w2 1000 usdt */

    await usdtW2.write.approve([fundContract.address, 1000n * 10n ** 18n]);
    /** invest 500*2 usdt */
    await fundContractW2.write.investInRound([0n, 2n]);
    const balanceOfW2 = await usdt.read.balanceOf([wallet2.account.address]);
    assert.equal(formatEther(balanceOfW2), "0");
    const round = await fundContract.read.investmentRounds([0n]);
    assert.equal(round[4], 1000n);
    const nftBalance = await nftContract.read.balanceOf([
      wallet2.account.address,
    ]);
    assert.equal(nftBalance, 2n);
    await fundContract.write.withdrawFund([0n]);
    const ownerUsdt = await usdt.read.balanceOf([wallet1.account.address]);
    assert.equal(formatEther(ownerUsdt), "2000");
    //** fast forward time 6 month */

    //** redeem nft 2 nft 1000 *6 % = 120/2 month = 60 */
    const beforeClaimW2Balance = await usdt.read.balanceOf([
      wallet2.account.address,
    ]);
    assert.equal(formatEther(beforeClaimW2Balance), "0");
    await usdt.write.mint([wallet1.account.address, 1060n * 10n ** 18n]);
    await usdt.write.approve([fundContract.address, 1060n * 10n ** 18n]);
    await fundContract.write.addRewardToRound([0n, 1060n]);
    const fundContractBalace = await usdt.read.balanceOf([
      fundContract.address,
    ]);

    assert.equal(formatEther(fundContractBalace), "1060");

    await networkHelpers.mine();
    await networkHelpers.time.increase(60 * 60 * 24 * 30 * 14);
    await networkHelpers.mine();

    await fundContractW2.write.claimRewardRound([0n]);

    const afterClaimW2Balance = await usdt.read.balanceOf([
      wallet2.account.address,
    ]);
    assert.equal(formatEther(afterClaimW2Balance), "1060");
  });

  it("Should test manual pagination with 10 rounds", async function () {
    const contract = await viem.getContractAt(
      "FundRaisingContractNFT",
      fundContractNFT.address
    );

    // Create 10 test rounds
    const currentTimeMs = Math.floor(Date.now() / 1000); // Current timestamp in milliseconds
    const rounds = [];

    for (let i = 0; i < 10; i++) {
      const roundName = `Test Round ${i + 1}`;
      const tokenPrice = parseEther(`${10 + i}`); // Different prices: 10, 11, 12, ... 19 USDT per token
      const rewardPercentage = BigInt(1200 + i * 100); // Different rewards: 12%, 13%, 14%, ... 21%
      const totalTokens = BigInt(1000 + i * 100); // Different token amounts: 1000, 1100, 1200, ... 1900
      const closeDate = BigInt(currentTimeMs + 86400000 * (30 + i)); // Different close dates (30+ days in future, in milliseconds)
      const endDate = BigInt(currentTimeMs + 86400000 * (365 + i)); // Different end dates (365+ days in future, in milliseconds)

      // Create the round
      await contract.write.createInvestmentRound([
        roundName,
        tokenPrice,
        rewardPercentage,
        totalTokens,
        closeDate,
        endDate,
      ]);

      rounds.push({
        name: roundName,
        price: tokenPrice,
        reward: rewardPercentage,
        tokens: totalTokens,
        roundId: BigInt(i),
      });
    }

    // Test manual pagination using available functions
    const [totalRounds, activeRounds] = await contract.read.getRoundsCount();
    assert.equal(totalRounds, 10n, "Should have 10 total rounds");

    // Test pagination: First page (offset=0, limit=5)
    const offset = 0n;
    const limit = 5n;
    const startIndex = Number(offset);
    const endIndex = Math.min(startIndex + Number(limit), Number(totalRounds));

    const firstPageRounds = [];
    for (let i = startIndex; i < endIndex; i++) {
      const round = await contract.read.investmentRounds([BigInt(i)]);
      firstPageRounds.push(round);
    }

    // Verify first page results
    assert.equal(firstPageRounds.length, 5, "First page should have 5 rounds");

    // Verify first page content (rounds 0-4)
    for (let i = 0; i < 5; i++) {
      assert.equal(
        firstPageRounds[i][0], // roundId is at index 0
        BigInt(i),
        `Round ${i} ID should match`
      );
      assert.equal(
        firstPageRounds[i][1], // roundName is at index 1
        `Test Round ${i + 1}`,
        `Round ${i} name should match`
      );
    }

    // Test pagination: Second page (offset=5, limit=5)
    const offset2 = 5n;
    const startIndex2 = Number(offset2);
    const endIndex2 = Math.min(
      startIndex2 + Number(limit),
      Number(totalRounds)
    );

    const secondPageRounds = [];
    for (let i = startIndex2; i < endIndex2; i++) {
      const round = await contract.read.investmentRounds([BigInt(i)]);
      secondPageRounds.push(round);
    }

    // Verify second page results
    assert.equal(
      secondPageRounds.length,
      5,
      "Second page should have 5 rounds"
    );

    // Verify second page content (rounds 5-9)
    for (let i = 0; i < 5; i++) {
      const roundIndex = i + 5;
      assert.equal(
        secondPageRounds[i][0], // roundId
        BigInt(roundIndex),
        `Round ${roundIndex} ID should match`
      );
      assert.equal(
        secondPageRounds[i][1], // roundName
        `Test Round ${roundIndex + 1}`,
        `Round ${roundIndex} name should match`
      );
    }

    // Test boundary case: request near end of data
    const offset3 = 8n;
    const startIndex3 = Number(offset3);
    const endIndex3 = Math.min(
      startIndex3 + Number(limit),
      Number(totalRounds)
    );

    const boundaryRounds = [];
    for (let i = startIndex3; i < endIndex3; i++) {
      const round = await contract.read.investmentRounds([BigInt(i)]);
      boundaryRounds.push(round);
    }

    assert.equal(
      boundaryRounds.length,
      2,
      "Should only get 2 rounds (8 and 9)"
    );
    assert.equal(boundaryRounds[0][0], 8n, "First round should be ID 8");
    assert.equal(boundaryRounds[1][0], 9n, "Second round should be ID 9");
  });

  it("Should test DZNFT wallet pagination with multiple NFTs", async function () {
    const contract = await viem.getContractAt(
      "FundRaisingContractNFT",
      fundContractNFT.address
    );
    const nft = await viem.getContractAt("DZNFT", nftContract.address);
    const usdt = await viem.getContractAt("MockUSDT", usdtContract.address);

    // Setup: Mint USDT to wallet2 for investments (like other tests)
    await usdt.write.mint([wallet2.account.address, 1000000000n * 10n ** 18n]);

    // Create a test round
    const currentTimeMs = Math.floor(Date.now() / 1000);
    await contract.write.createInvestmentRound([
      "Test Round for NFT Pagination",
      500n, // 500 wei per token (like other tests)
      1500n, // 15% reward
      1000n, // 1000 tokens available
      BigInt(currentTimeMs + 86400000 * 30), // 30 days from now
      BigInt(currentTimeMs + 86400000 * 365), // 1 year from now
    ]);

    // Setup contract for wallet2
    const contractW2 = await viem.getContractAt(
      "FundRaisingContractNFT",
      fundContractNFT.address,
      { client: { wallet: wallet2 } }
    );
    const usdtW2 = await viem.getContractAt("MockUSDT", usdtContract.address, {
      client: { wallet: wallet2 },
    });

    // Approve USDT for investments (use same amount as other tests)
    await usdtW2.write.approve([
      fundContractNFT.address,
      1000000000n * 10n ** 18n,
    ]);

    // Make multiple investments to create 7 NFTs
    const investmentAmounts = [1n, 2n, 1n, 3n]; // Total: 7 NFTs
    for (const amount of investmentAmounts) {
      await contractW2.write.investInRound([0n, amount]);
    }

    // Test: Get all NFTs owned by wallet2 (should be 7)
    const allTokenIds = await nft.read.getWalletTokenIds([
      wallet2.account.address,
    ]);
    assert.equal(allTokenIds.length, 7, "Should have 7 NFTs total");

    // Test: Get wallet NFT summary
    const summary = await nft.read.getWalletNFTSummary([
      wallet2.account.address,
    ]);
    const [
      totalNFTs,
      activeInvestments,
      redeemedInvestments,
      claimedRewards,
      totalInvestedValue,
      totalExpectedRewards,
      claimableAmount,
    ] = summary;

    assert.equal(totalNFTs, 7n, "Summary should show 7 total NFTs");
    assert.equal(activeInvestments, 7n, "Should have 7 active investments");
    assert.equal(redeemedInvestments, 0n, "Should have 0 redeemed investments");
    assert.equal(claimedRewards, 0n, "Should have 0 claimed rewards");
    assert.equal(
      totalInvestedValue,
      3500n * 10n ** 18n,
      "Total invested should be 3500 * 10^18 wei (7 tokens * 500 * 10^18 wei)"
    );

    // Test pagination: First page (offset=0, limit=3)
    const firstPage = await nft.read.getWalletNFTsPaginated([
      wallet2.account.address,
      0n, // offset
      3n, // limit
    ]);

    const [
      firstPageTokenIds,
      firstPageDetails,
      firstPageTotal,
      firstPageTotalPages,
      firstPageCurrentPage,
      firstPageHasMore,
    ] = firstPage;

    // Verify first page results
    assert.equal(firstPageTokenIds.length, 3, "First page should have 3 NFTs");
    assert.equal(
      firstPageDetails.length,
      3,
      "First page should have 3 investment details"
    );
    assert.equal(firstPageTotal, 7n, "Total should be 7");
    assert.equal(
      firstPageTotalPages,
      3n,
      "Should have 3 total pages (7/3 = 2.33 -> 3)"
    );
    assert.equal(firstPageCurrentPage, 1n, "Should be on page 1");
    assert.equal(firstPageHasMore, true, "Should have more pages");

    // Verify first page content
    for (let i = 0; i < 3; i++) {
      assert.equal(
        firstPageDetails[i].roundId,
        0n,
        `NFT ${i} should be from round 0`
      );
      assert.equal(
        firstPageDetails[i].originalBuyer.toLowerCase(),
        wallet2.account.address.toLowerCase(),
        `NFT ${i} should be owned by wallet2`
      );
      assert.equal(
        firstPageDetails[i].tokenPrice,
        500n * 10n ** 18n,
        `NFT ${i} should have correct token price`
      );
      assert.equal(
        firstPageDetails[i].rewardPercentage,
        1500n,
        `NFT ${i} should have correct reward percentage`
      );
      assert.equal(
        firstPageDetails[i].redeemed,
        false,
        `NFT ${i} should not be redeemed`
      );
      assert.equal(
        firstPageDetails[i].rewardClaimed,
        false,
        `NFT ${i} should not have reward claimed`
      );
    }

    // Test pagination: Second page (offset=3, limit=3)
    const secondPage = await nft.read.getWalletNFTsPaginated([
      wallet2.account.address,
      3n, // offset
      3n, // limit
    ]);

    const [
      secondPageTokenIds,
      secondPageDetails,
      secondPageTotal,
      secondPageTotalPages,
      secondPageCurrentPage,
      secondPageHasMore,
    ] = secondPage;

    // Verify second page results
    assert.equal(
      secondPageTokenIds.length,
      3,
      "Second page should have 3 NFTs"
    );
    assert.equal(secondPageTotal, 7n, "Total should still be 7");
    assert.equal(secondPageTotalPages, 3n, "Should still have 3 total pages");
    assert.equal(secondPageCurrentPage, 2n, "Should be on page 2");
    assert.equal(secondPageHasMore, true, "Should still have more pages");

    // Test pagination: Third page (offset=6, limit=3) - should only have 1 NFT
    const thirdPage = await nft.read.getWalletNFTsPaginated([
      wallet2.account.address,
      6n, // offset
      3n, // limit
    ]);

    const [thirdPageTokenIds, , , , thirdPageCurrentPage, thirdPageHasMore] =
      thirdPage;

    // Verify third page results
    assert.equal(thirdPageTokenIds.length, 1, "Third page should have 1 NFT");
    assert.equal(thirdPageCurrentPage, 3n, "Should be on page 3");
    assert.equal(thirdPageHasMore, false, "Should not have more pages");

    // Test edge case: Empty wallet
    const emptyWalletResult = await nft.read.getWalletNFTsPaginated([
      wallet3.account.address, // wallet3 has no NFTs
      0n,
      10n,
    ]);

    const [
      emptyTokenIds,
      emptyDetails,
      emptyTotal,
      emptyTotalPages,
      emptyCurrentPage,
      emptyHasMore,
    ] = emptyWalletResult;
    assert.equal(emptyTokenIds.length, 0, "Empty wallet should have 0 NFTs");
    assert.equal(emptyTotal, 0n, "Empty wallet should have 0 total");
    assert.equal(emptyTotalPages, 0n, "Empty wallet should have 0 pages");
    assert.equal(emptyCurrentPage, 0n, "Empty wallet should be on page 0");
    assert.equal(
      emptyHasMore,
      false,
      "Empty wallet should not have more pages"
    );

    // Verify all token IDs are unique and belong to wallet2
    const allUniqueIds = new Set(allTokenIds.map((id) => id.toString()));
    assert.equal(allUniqueIds.size, 7, "All token IDs should be unique");

    // Verify all NFTs belong to wallet2
    for (const tokenId of allTokenIds) {
      const owner = await nft.read.ownerOf([tokenId]);
      assert.equal(
        owner.toLowerCase(),
        wallet2.account.address.toLowerCase(),
        `Token ${tokenId} should be owned by wallet2`
      );
    }
  });

  it("Should allowance success", async function () {
    await usdtContract.write.approve([
      fundContractNFT.address,
      500n * 10n ** 18n,
    ]);
    const allowance = await usdtContract.read.allowance([
      wallet1.account.address,
      fundContractNFT.address,
    ]);
    assert.equal(allowance, 500n * 10n ** 18n);
  });

  it("Should display round list with last created round first", async function () {
    const contract = await viem.getContractAt(
      "FundRaisingContractNFT",
      fundContractNFT.address
    );

    // Create multiple rounds with different creation times
    const currentTimeMs = Math.floor(Date.now() / 1000);
    const roundsData = [];

    for (let i = 0; i < 5; i++) {
      const roundName = `Round ${i + 1}`;
      const tokenPrice = parseEther(`${100 + i * 50}`); // Different prices: 100, 150, 200, 250, 300 USDT
      const rewardPercentage = BigInt(1000 + i * 200); // Different rewards: 10%, 12%, 14%, 16%, 18%
      const totalTokens = BigInt(500 + i * 100); // Different token amounts: 500, 600, 700, 800, 900
      const closeDate = BigInt(currentTimeMs + 86400000 * (30 + i * 10)); // Different close dates
      const endDate = BigInt(currentTimeMs + 86400000 * (365 + i * 30)); // Different end dates

      // Create the round
      await contract.write.createInvestmentRound([
        roundName,
        tokenPrice,
        rewardPercentage,
        totalTokens,
        closeDate,
        endDate,
      ]);

      roundsData.push({
        id: i,
        name: roundName,
        price: tokenPrice,
        reward: rewardPercentage,
        tokens: totalTokens,
        createdOrder: i, // Order of creation (0 = first, 4 = last)
      });
    }

    // Get total rounds count
    const [totalRounds, activeRounds] = await contract.read.getRoundsCount();
    assert.equal(totalRounds, 5n, "Should have 5 total rounds");

    // Fetch all rounds and display them in reverse order (last created first)
    const allRounds = [];
    for (let i = 0; i < Number(totalRounds); i++) {
      const round = await contract.read.investmentRounds([BigInt(i)]);

      allRounds.push({
        roundId: round[0], // roundId
        roundName: round[1], // roundName
        tokenPrice: round[2], // tokenPrice
        rewardPercentage: round[3], // rewardPercentage
        totalTokens: round[4], // totalTokenOpenInvestment (index 4)
        creationIndex: i, // Original creation order
      });
    }

    // Sort rounds by creation order in descending order (last created first)
    const sortedRounds = allRounds.sort(
      (a, b) => Number(b.roundId) - Number(a.roundId)
    );

    // Verify the sorting - last created round should be first
    assert.equal(sortedRounds.length, 5, "Should have 5 rounds");
    assert.equal(
      sortedRounds[0].roundName,
      "Round 5",
      "First in list should be Round 5 (last created)"
    );
    assert.equal(
      sortedRounds[1].roundName,
      "Round 4",
      "Second in list should be Round 4"
    );
    assert.equal(
      sortedRounds[2].roundName,
      "Round 3",
      "Third in list should be Round 3"
    );
    assert.equal(
      sortedRounds[3].roundName,
      "Round 2",
      "Fourth in list should be Round 2"
    );
    assert.equal(
      sortedRounds[4].roundName,
      "Round 1",
      "Last in list should be Round 1 (first created)"
    );

    // Verify round IDs are in descending order
    for (let i = 0; i < sortedRounds.length - 1; i++) {
      assert(
        sortedRounds[i].roundId > sortedRounds[i + 1].roundId,
        `Round ${i} ID should be greater than Round ${i + 1} ID`
      );
    }

    // Test pagination with reverse order (last created first)
    const pageSize = 3;
    const firstPageOffset = 0;

    // Get first page (3 most recent rounds)
    const firstPageStart = Number(totalRounds) - 1 - firstPageOffset; // Start from last created
    const firstPageEnd = Math.max(firstPageStart - pageSize + 1, 0); // Go backwards

    const firstPageRounds = [];
    for (let i = firstPageStart; i >= firstPageEnd; i--) {
      if (i >= 0) {
        const round = await contract.read.investmentRounds([BigInt(i)]);
        firstPageRounds.push({
          roundId: round[0],
          roundName: round[1],
          tokenPrice: round[2],
          rewardPercentage: round[3],
        });
      }
    }

    // Verify first page contains the 3 most recent rounds
    assert.equal(firstPageRounds.length, 3, "First page should have 3 rounds");
    assert.equal(
      firstPageRounds[0].roundName,
      "Round 5",
      "First page first item should be Round 5"
    );
    assert.equal(
      firstPageRounds[1].roundName,
      "Round 4",
      "First page second item should be Round 4"
    );
    assert.equal(
      firstPageRounds[2].roundName,
      "Round 3",
      "First page third item should be Round 3"
    );

    // Test second page (remaining 2 rounds)
    const secondPageOffset = 3;
    const secondPageStart = Number(totalRounds) - 1 - secondPageOffset;
    const secondPageEnd = Math.max(secondPageStart - pageSize + 1, 0);

    const secondPageRounds = [];
    for (let i = secondPageStart; i >= secondPageEnd; i--) {
      if (i >= 0) {
        const round = await contract.read.investmentRounds([BigInt(i)]);
        secondPageRounds.push({
          roundId: round[0],
          roundName: round[1],
        });
      }
    }

    // Verify second page contains the 2 oldest rounds
    assert.equal(
      secondPageRounds.length,
      2,
      "Second page should have 2 rounds"
    );
    assert.equal(
      secondPageRounds[0].roundName,
      "Round 2",
      "Second page first item should be Round 2"
    );
    assert.equal(
      secondPageRounds[1].roundName,
      "Round 1",
      "Second page second item should be Round 1"
    );

    // Display summary of rounds in reverse chronological order
    console.log("\n=== Rounds List (Last Created First) ===");
    sortedRounds.forEach((round, index) => {
      console.log(`${index + 1}. ${round.roundName} (ID: ${round.roundId})`);
      console.log(`   Token Price: ${formatEther(round.tokenPrice)} USDT`);
      console.log(`   Reward: ${Number(round.rewardPercentage) / 100}%`);
      console.log(`   Total Tokens: ${round.totalTokens}`);
      console.log("");
    });
  });

  it("Should use helper function to get rounds in reverse order with pagination", async function () {
    const contract = await viem.getContractAt(
      "FundRaisingContractNFT",
      fundContractNFT.address
    );

    // Create 3 test rounds
    const currentTimeMs = Math.floor(Date.now() / 1000);
    for (let i = 0; i < 3; i++) {
      await contract.write.createInvestmentRound([
        `Helper Test Round ${i + 1}`,
        parseEther(`${50 + i * 25}`), // 50, 75, 100 USDT
        BigInt(800 + i * 200), // 8%, 10%, 12%
        BigInt(100 + i * 50), // 100, 150, 200 tokens
        BigInt(currentTimeMs + 86400000 * 30),
        BigInt(currentTimeMs + 86400000 * 365),
      ]);
    }

    // Test helper function - get all rounds in reverse order
    const allRounds = await getRoundsReversed(contract);
    assert.equal(allRounds.length, 3, "Should get all 3 rounds");
    assert.equal(
      allRounds[0].roundName,
      "Helper Test Round 3",
      "First should be last created"
    );
    assert.equal(
      allRounds[1].roundName,
      "Helper Test Round 2",
      "Second should be middle"
    );
    assert.equal(
      allRounds[2].roundName,
      "Helper Test Round 1",
      "Third should be first created"
    );

    // Test pagination with helper function - first page (limit 2)
    const firstPage = await getRoundsReversed(contract, 0, 2);
    assert.equal(firstPage.length, 2, "First page should have 2 rounds");
    assert.equal(
      firstPage[0].roundName,
      "Helper Test Round 3",
      "First page first item"
    );
    assert.equal(
      firstPage[1].roundName,
      "Helper Test Round 2",
      "First page second item"
    );

    // Test pagination with helper function - second page (offset 2, limit 2)
    const secondPage = await getRoundsReversed(contract, 2, 2);
    assert.equal(secondPage.length, 1, "Second page should have 1 round");
    assert.equal(
      secondPage[0].roundName,
      "Helper Test Round 1",
      "Second page first item"
    );

    console.log("\n=== Helper Function Test - Rounds in Reverse Order ===");
    allRounds.forEach((round, index) => {
      console.log(`${index + 1}. ${round.roundName} (ID: ${round.roundId})`);
      console.log(
        `   Tokens: ${round.totalTokens}, Reward: ${
          round.rewardPercentage / 100
        }%`
      );
    });
  });
});
