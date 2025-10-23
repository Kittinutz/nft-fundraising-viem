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

    // Test getAllRoundsDetailedPaginated with sorting
    const offset = 0n;
    const limit = 10n;
    const sortField = 2; // CREATED_AT (enum value)
    const sortDirection = 1; // DESC (enum value)

    const roundList = await contract.read.getAllRoundsDetailedPaginated([
      offset,
      limit,
      sortField,
      sortDirection,
    ]);

    // Verify we got results
    assert.equal(roundList[0].length, 1); // rounds array should have 1 round
    assert.equal(roundList[1].length, 1); // investorCounts array should have 1 entry
    assert.equal(roundList[0][0].roundName, roundName); // verify round name
    assert.equal(roundList[0][0].roundId, 0n); // verify round ID is 0
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
      500n,
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
      Date.now() + 30 * 24 * 60 * 60 * 1000,
      Date.now() + 365 * 24 * 60 * 60 * 1000,
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
    await fundContract.write.addReward([0n, 30n]);
    const fundContractBalace = await usdt.read.balanceOf([
      fundContract.address,
    ]);

    assert.equal(formatEther(fundContractBalace), "30");

    const block = await publicClient.getBlock();

    await networkHelpers.mine();
    await networkHelpers.time.increase(60 * 60 * 24 * 30 * 6);
    await networkHelpers.mine();

    await fundContractW2.write.claimRewardRound([0n]);

    const afterClaimW2Balance = await usdt.read.balanceOf([
      wallet2.account.address,
    ]);
    assert.equal(formatEther(afterClaimW2Balance), "30");

    await usdt.write.mint([wallet1.account.address, 1030n * 10n ** 18n]);
    await usdt.write.approve([fundContract.address, 1030n * 10n ** 18n]);
    await fundContract.write.addReward([0n, 1030n]);
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
    await fundContract.write.createInvestmentRound([
      "Round 1",
      500n,
      6n,
      1000n,
      Date.now() + 30 * 24 * 60 * 60 * 1000,
      Date.now() + 365 * 24 * 60 * 60 * 1000,
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
    await fundContract.write.addReward([0n, 1060n]);
    const fundContractBalace = await usdt.read.balanceOf([
      fundContract.address,
    ]);

    assert.equal(formatEther(fundContractBalace), "1060");

    await networkHelpers.mine();
    await networkHelpers.time.increase(60 * 60 * 24 * 30 * 13);
    await networkHelpers.mine();

    await fundContractW2.write.claimRewardRound([0n]);

    const afterClaimW2Balance = await usdt.read.balanceOf([
      wallet2.account.address,
    ]);
    assert.equal(formatEther(afterClaimW2Balance), "1060");
  });

  it("Should test getAllRoundsDetailedPaginated with 10 rounds and pagination", async function () {
    const contract = await viem.getContractAt(
      "FundRaisingContractNFT",
      fundContractNFT.address
    );

    // Create 10 test rounds
    const currentTimeMs = Date.now(); // Current timestamp in milliseconds
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

    // Test pagination: First page (offset=0, limit=5)
    const firstPageResult = await contract.read.getAllRoundsDetailedPaginated([
      0n, // offset
      5n, // limit
      0, // sortField: ID
      0, // sortDirection: ASC
    ]);

    const [
      firstPageRounds,
      firstPageInvestorCounts,
      firstPageTotalPages,
      firstPageCurrentPage,
      firstPageHasMore,
    ] = firstPageResult;

    // Verify first page results
    assert.equal(firstPageRounds.length, 5, "First page should have 5 rounds");
    assert.equal(
      firstPageInvestorCounts.length,
      5,
      "First page should have 5 investor counts"
    );
    assert.equal(firstPageTotalPages, 2n, "Should have 2 total pages");
    assert.equal(firstPageCurrentPage, 1n, "Should be on page 1");
    assert.equal(firstPageHasMore, true, "Should have more pages");

    // Verify first page content (rounds 0-4)
    for (let i = 0; i < 5; i++) {
      assert.equal(
        firstPageRounds[i].roundId,
        BigInt(i),
        `Round ${i} ID should match`
      );
      assert.equal(
        firstPageRounds[i].roundName,
        `Test Round ${i + 1}`,
        `Round ${i} name should match`
      );
      assert.equal(
        firstPageInvestorCounts[i],
        0n,
        `Round ${i} should have 0 investors`
      );
    }

    // Test pagination: Second page (offset=5, limit=5)
    const secondPageResult = await contract.read.getAllRoundsDetailedPaginated([
      5n, // offset
      5n, // limit
      0, // sortField: ID
      0, // sortDirection: ASC
    ]);

    const [
      secondPageRounds,
      secondPageInvestorCounts,
      secondPageTotalPages,
      secondPageCurrentPage,
      secondPageHasMore,
    ] = secondPageResult;

    // Verify second page results
    assert.equal(
      secondPageRounds.length,
      5,
      "Second page should have 5 rounds"
    );
    assert.equal(
      secondPageInvestorCounts.length,
      5,
      "Second page should have 5 investor counts"
    );
    assert.equal(secondPageTotalPages, 2n, "Should have 2 total pages");
    assert.equal(secondPageCurrentPage, 2n, "Should be on page 2");
    assert.equal(secondPageHasMore, false, "Should not have more pages");

    // Verify second page content (rounds 5-9)
    for (let i = 0; i < 5; i++) {
      const roundIndex = i + 5;
      assert.equal(
        secondPageRounds[i].roundId,
        BigInt(roundIndex),
        `Round ${roundIndex} ID should match`
      );
      assert.equal(
        secondPageRounds[i].roundName,
        `Test Round ${roundIndex + 1}`,
        `Round ${roundIndex} name should match`
      );
      assert.equal(
        secondPageInvestorCounts[i],
        0n,
        `Round ${roundIndex} should have 0 investors`
      );
    }

    // Test sorting: Get all rounds sorted by reward percentage DESC
    const sortedResult = await contract.read.getAllRoundsDetailedPaginated([
      0n, // offset
      10n, // limit (get all)
      6, // sortField: REWARD_PERCENTAGE
      1, // sortDirection: DESC
    ]);

    const [sortedRounds] = sortedResult;

    // Verify sorting - highest reward percentage first
    assert.equal(sortedRounds.length, 10, "Should get all 10 rounds");
    assert.equal(
      sortedRounds[0].rewardPercentage,
      2100n,
      "First round should have highest reward (21%)"
    );
    assert.equal(
      sortedRounds[9].rewardPercentage,
      1200n,
      "Last round should have lowest reward (12%)"
    );

    // Verify descending order
    for (let i = 0; i < 9; i++) {
      assert(
        sortedRounds[i].rewardPercentage >=
          sortedRounds[i + 1].rewardPercentage,
        `Round ${i} reward should be >= Round ${i + 1} reward`
      );
    }

    // Test boundary case: request near end of data
    const boundaryResult = await contract.read.getAllRoundsDetailedPaginated([
      8n, // offset near end
      5n, // limit
      0, // sortField: ID
      0, // sortDirection: ASC
    ]);

    const [boundaryRounds, , , , boundaryHasMore] = boundaryResult;
    assert.equal(
      boundaryRounds.length,
      2,
      "Should only get 2 rounds (8 and 9)"
    );
    assert.equal(boundaryHasMore, false, "Should not have more pages");
    assert.equal(boundaryRounds[0].roundId, 8n, "First round should be ID 8");
    assert.equal(boundaryRounds[1].roundId, 9n, "Second round should be ID 9");
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
    const currentTimeMs = Date.now();
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
});
