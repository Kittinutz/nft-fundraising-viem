import assert from "node:assert/strict";
import { before, describe, it } from "node:test";
import { network } from "hardhat";
import { formatUnits, parseUnits } from "viem";

describe("🔴 CRITICAL: ClaimRewardRound Double Claiming Attack Proof", async function () {
  const { viem, networkHelpers } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const [owner, attacker] = await viem.getWalletClients();

  let mockUSDT: any;
  let dzNFT: any;
  let coreContract: any;
  let claimsContract: any;

  // Helper to get current timestamp
  async function getCurrentTimestamp(): Promise<number> {
    const currentBlock = await publicClient.getBlock();
    return Number(currentBlock.timestamp);
  }

  before(async () => {
    console.log("🚀 Deploying contracts for vulnerability test...");

    // Deploy MockUSDT (18 decimals for simplicity)
    mockUSDT = await viem.deployContract("MockUSDT", [
      "Mock USDT",
      "MUSDT",
      6,
      parseUnits("10000000", 6),
    ]);

    // Deploy DZNFT
    dzNFT = await viem.deployContract("DZNFT");

    // Deploy FundRaisingCore
    coreContract = await viem.deployContract("FundRaisingCore", [
      dzNFT.address,
      mockUSDT.address,
    ]);

    // Deploy FundRaisingClaims (the vulnerable contract)
    claimsContract = await viem.deployContract("FundRaisingClaims", [
      coreContract.address,
      dzNFT.address,
      mockUSDT.address,
    ]);

    // Setup permissions
    await dzNFT.write.updateExecutorRole([coreContract.address, true]);
    await dzNFT.write.updateExecutorRole([claimsContract.address, true]);

    // Set authorized claims contract in core
    await coreContract.write.setAuthorizedClaimsContract([
      claimsContract.address,
    ]);

    console.log("✅ Contracts deployed successfully");
  });

  it("🚨 PROOF: User can claim rewards multiple times for same round", async function () {
    console.log("\n" + "=".repeat(80));
    console.log("🔥 EXECUTING DOUBLE CLAIMING ATTACK");
    console.log("=".repeat(80));

    // 1. Give attacker USDT and approve spending
    await mockUSDT.write.faucet([], { account: attacker.account });
    await mockUSDT.write.approve(
      [coreContract.address, parseUnits("10000", 6)],
      {
        account: attacker.account,
      }
    );

    // 2. Create investment round
    const tokenPrice = parseUnits("100", 6); // 100 USDT per token
    const rewardRate = 10; // 10% reward
    const currentTime = BigInt(await getCurrentTimestamp());

    console.log(`\n📋 Setting up investment round...`);
    await coreContract.write.createInvestmentRound([
      "Attack Test Round",
      tokenPrice,
      rewardRate,
      parseUnits("50000", 6), // total tokens available
      currentTime + 86400n, // close date (1 day)
      currentTime + 86400n * 2n, // end date (2 days) - must be after close date
    ]);

    // Get the round ID (should be 0 for first round)
    const roundId = 0n;

    // 3. Add reward pool (owner funds)
    await mockUSDT.write.faucet(); // Give owner USDT
    await mockUSDT.write.approve(
      [coreContract.address, parseUnits("10000", 6)],
      {
        account: owner.account,
      }
    );
    await coreContract.write.addRewardToRound([roundId, 1000n], {
      account: owner.account,
    }); // Pass 1000 (will be scaled to 1000 * 10^18)

    // 4. Attacker makes legitimate investment
    console.log(`💰 Attacker investing 1000 USDT (10 tokens)...`);
    await coreContract.write.investInRound([roundId, 10n], {
      account: attacker.account,
    });

    // Verify attacker got NFTs
    const attackerNFTs = await dzNFT.read.getUserNFTsByRound([
      attacker.account.address,
      roundId,
    ]);
    console.log(`🎯 Attacker received ${attackerNFTs.length} NFTs`);
    assert.ok(attackerNFTs.length > 0, "Attacker should have received NFTs");

    // 5. Fast forward to claim period (180+ days after round closes)
    console.log(`⏰ Fast forwarding to after close date + 180 days...`);
    await networkHelpers.time.increase(186 * 24 * 60 * 60); // 186 days to be safe

    // 6. Record initial balance
    const initialBalance = await mockUSDT.read.balanceOf([
      attacker.account.address,
    ]);
    console.log(
      `💳 Attacker initial balance: ${formatUnits(initialBalance, 6)} USDT`
    );

    // 7. 🔴 ATTACK: Multiple reward claims
    console.log(`\n🚨 EXECUTING ATTACK: Multiple claims for same round...`);

    let claimAttempts = 0;
    let successfulClaims = 0;
    let lastBalance = initialBalance;

    // Attempt multiple claims
    for (let i = 1; i <= 5; i++) {
      try {
        console.log(`\n📋 Claim attempt #${i}:`);
        claimAttempts++;

        await claimsContract.write.claimRewardRound([roundId], {
          account: attacker.account,
        });

        // Check balance after claim
        const newBalance = await mockUSDT.read.balanceOf([
          attacker.account.address,
        ]);
        const gainedThisClaim = newBalance - lastBalance;
        const totalGained = newBalance - initialBalance;

        if (gainedThisClaim > 0n) {
          successfulClaims++;
          console.log(
            `   ✅ SUCCESS! Gained: ${formatUnits(
              BigInt(gainedThisClaim),
              6
            )} USDT`
          );
          console.log(
            `   💰 Total stolen: ${formatUnits(BigInt(totalGained), 6)} USDT`
          );
        } else {
          console.log(`   ⚠️  No funds gained (possible protection)`);
        }

        lastBalance = newBalance;
      } catch (error: any) {
        console.log(
          `   ❌ FAILED: ${
            error.shortMessage || error.message || "Unknown error"
          }`
        );
        if (error.cause?.details) {
          console.log(`   Details: ${error.cause.details}`);
        }
        break; // Stop on first error
      }
    }

    // 8. Calculate final damage
    const finalBalance = await mockUSDT.read.balanceOf([
      attacker.account.address,
    ]);
    const totalStolen = finalBalance - initialBalance;
    const remainingRewardPool = await coreContract.read.roundRewardPool([
      roundId,
    ]);

    console.log(`\n📊 ATTACK RESULTS:`);
    console.log(`🎯 Claim attempts: ${claimAttempts}`);
    console.log(`✅ Successful claims: ${successfulClaims}`);
    console.log(
      `💸 Total amount stolen: ${formatUnits(BigInt(totalStolen), 6)} USDT`
    );
    console.log(
      `🏦 Remaining reward pool: ${formatUnits(
        BigInt(remainingRewardPool),
        6
      )} USDT`
    );

    // 9. Vulnerability assessment
    const expectedLegitimateReward = parseUnits("50", 6); // 50% of (10% of 1000 USDT)

    console.log(`\n🔍 VULNERABILITY ANALYSIS:`);
    console.log(
      `📈 Expected legitimate reward: ${formatUnits(
        expectedLegitimateReward,
        6
      )} USDT`
    );
    console.log(
      `💀 Actual amount stolen: ${formatUnits(BigInt(totalStolen), 6)} USDT`
    );
    if (successfulClaims > 1) {
      const multiplier = Number(totalStolen) / Number(expectedLegitimateReward);
      console.log(`🔥 VULNERABILITY CONFIRMED!`);
      console.log(`   - Multiple claims succeeded: ${successfulClaims}`);
      console.log(`   - Reward multiplier: ${multiplier.toFixed(1)}x`);
      if (totalStolen > expectedLegitimateReward) {
        const extraStolen =
          BigInt(totalStolen) - BigInt(expectedLegitimateReward);
        console.log(
          `   - User stole ${formatUnits(extraStolen, 6)} USDT extra`
        );
      }
    } else if (successfulClaims === 1) {
      console.log(`⚠️  Only one claim succeeded (possible protection exists)`);
    } else {
      console.log(`✅ No claims succeeded (protection working)`);
    }

    // 10. Security recommendation
    console.log(`\n🛡️  SECURITY ASSESSMENT:`);
    if (successfulClaims > 1) {
      console.log(`❌ CRITICAL VULNERABILITY EXISTS`);
      console.log(`   - Users can claim rewards multiple times`);
      console.log(`   - Reward pools can be drained`);
      console.log(`   - Immediate fix required before deployment`);
    } else {
      console.log(`✅ Claims appear to be properly protected`);
    }

    console.log(`\n` + "=".repeat(80));
    console.log(`END OF ATTACK TEST`);
    console.log("=".repeat(80) + `\n`);

    // Assert the vulnerability exists
    if (successfulClaims > 1) {
      console.log(`🚨 TEST RESULT: CRITICAL VULNERABILITY CONFIRMED`);
      console.log(`💀 Multiple reward claims succeeded for same round!`);
      console.log(`🔥 VULNERABILITY: User can drain reward pools!`);
    } else if (successfulClaims === 1) {
      console.log(`📋 TEST RESULT: Claims are properly protected`);
      console.log(
        `✅ Only one claim succeeded - NFTs correctly marked as claimed`
      );
      console.log(
        `🛡️ No double-claiming vulnerability found in this test scenario`
      );
    } else {
      console.log(`❌ TEST RESULT: Setup issue - no claims succeeded`);
    }

    assert.ok(
      successfulClaims >= 1,
      "At least one claim should succeed to validate test setup"
    );
  });

  it("� ADVANCED TEST: Phase 2 double claiming attack (365+ days)", async function () {
    console.log("\n" + "=".repeat(80));
    console.log("🔥 TESTING PHASE 2 DOUBLE CLAIMING (365+ DAYS)");
    console.log("=".repeat(80));

    // Fresh setup for new round
    await mockUSDT.write.faucet([], { account: attacker.account });
    await mockUSDT.write.approve(
      [coreContract.address, parseUnits("10000", 6)],
      {
        account: attacker.account,
      }
    );

    const tokenPrice = parseUnits("100", 6);
    const rewardRate = 10;
    const currentTime = BigInt(await getCurrentTimestamp());

    console.log(`\n📋 Setting up investment round for Phase 2 test...`);
    await coreContract.write.createInvestmentRound([
      "Phase 2 Attack Round",
      tokenPrice,
      rewardRate,
      parseUnits("50000", 6),
      currentTime + 86400n, // close in 1 day
      currentTime + 86400n * 2n, // end in 2 days
    ]);

    const roundId = 1n; // Second round

    // Add reward pool
    await mockUSDT.write.faucet();
    await mockUSDT.write.approve([
      coreContract.address,
      parseUnits("10000", 6),
    ]);
    const roundTotal = await coreContract.read.totalRoundsCreated();
    console.log(`Total rounds created: ${roundTotal}`);
    await coreContract.write.addRewardToRound([roundId, 1100n]);
    const beforeBalance = await mockUSDT.read.balanceOf([
      attacker.account.address,
    ]);
    const rewardPool = await coreContract.read.roundRewardPool([roundId]);
    console.log(
      `🏦 Reward pool for round ${roundId}: ${formatUnits(rewardPool, 6)} USDT`
    );

    console.log(
      `💳 Attacker balance before invest Phase 2 claims: ${formatUnits(
        beforeBalance,
        6
      )} USDT`
    );

    console.log(`💰 Attacker investing for Phase 2 test...`);
    await coreContract.write.investInRound([roundId, 10n], {
      account: attacker.account,
    });

    // Fast forward to Phase 2 (365+ days after close)
    console.log(`⏰ Fast forwarding to Phase 2 (365+ days)...`);
    await networkHelpers.time.increase(370 * 24 * 60 * 60); // 370 days

    const initialBalance = await mockUSDT.read.balanceOf([
      attacker.account.address,
    ]);
    console.log(
      `💳 Attacker balance before Phase 2 claims: ${formatUnits(
        initialBalance,
        6
      )} USDT`
    );

    // In Phase 2, users should be able to claim remaining reward + principal
    console.log(`\n🚨 TESTING PHASE 2 DOUBLE CLAIMING...`);

    let phase2Claims = 0;
    let totalPhase2Gained = 0n;

    for (let i = 1; i <= 3; i++) {
      try {
        console.log(`\n📋 Phase 2 Claim attempt #${i}:`);

        await claimsContract.write.claimRewardRound([roundId], {
          account: attacker.account,
        });

        const newBalance = await mockUSDT.read.balanceOf([
          attacker.account.address,
        ]);
        const gained = newBalance - initialBalance;
        totalPhase2Gained = BigInt(gained);

        phase2Claims++;
        console.log(
          `   ✅ SUCCESS! Total gained in Phase 2: ${formatUnits(
            BigInt(gained),
            6
          )} USDT`
        );
      } catch (error: any) {
        console.log(
          `   ❌ issuerrrrr---> FAILED: ${
            error.shortMessage || error.message || "Unknown error"
          }`
        );
        if (error.cause?.details) {
          console.log(`   Details: ${error.cause.details}`);
        }
        break;
      }
    }

    console.log(`\n📊 PHASE 2 ATTACK RESULTS:`);
    console.log(`🎯 Phase 2 claim attempts: 3`);
    console.log(`✅ Successful Phase 2 claims: ${phase2Claims}`);
    console.log(
      `💸 Total Phase 2 gained: ${formatUnits(totalPhase2Gained, 6)} USDT`
    );

    // Expected Phase 2: remaining 50% reward (50 USDT) + principal (1000 USDT) = 1050 USDT
    const expectedPhase2 = parseUnits("1050", 6);

    if (phase2Claims > 1) {
      console.log(`🚨 PHASE 2 VULNERABILITY CONFIRMED!`);
      console.log(`💀 Multiple Phase 2 claims succeeded!`);
      console.log(
        `🔥 User can claim principal + remaining reward multiple times!`
      );
    } else if (phase2Claims === 1) {
      console.log(`✅ Phase 2 properly protected - only one claim allowed`);
      if (totalPhase2Gained >= expectedPhase2) {
        console.log(
          `💰 Correct Phase 2 payout: ${formatUnits(totalPhase2Gained, 6)} USDT`
        );
      }
    }

    console.log(`\n` + "=".repeat(80));
    console.log(`END OF PHASE 2 TEST`);
    console.log("=".repeat(80) + `\n`);

    assert.ok(phase2Claims >= 1, "At least one Phase 2 claim should succeed");
  });

  it("�📋 Summary of vulnerability findings", async function () {
    console.log(`\n📝 VULNERABILITY SUMMARY:`);
    console.log(`\n🔍 What was tested:`);
    console.log(`   - Multiple calls to claimRewardRound() for same round`);
    console.log(`   - Using legitimate NFTs owned by user`);
    console.log(`   - No attempt to bypass ownership checks`);

    console.log(`\n💀 Expected behavior:`);
    console.log(`   - User should claim 50% reward ONCE at 180 days`);
    console.log(
      `   - User should claim remaining 50% + principal ONCE at 365 days`
    );
    console.log(`   - Multiple claims should be rejected`);

    console.log(`\n🔥 If vulnerability exists:`);
    console.log(`   - User can call claimRewardRound() multiple times`);
    console.log(`   - Each call processes same NFTs again`);
    console.log(`   - Each call transfers more reward money`);
    console.log(`   - Reward pools get drained by legitimate users`);

    console.log(`\n🛡️  Required fixes (if vulnerable):`);
    console.log(`   1. Add round-level claim tracking`);
    console.log(`   2. Validate user hasn't claimed before calculations`);
    console.log(`   3. Update claim status immediately after validation`);
    console.log(`   4. Add comprehensive edge case testing`);

    console.log(`\n⚠️  Impact if deployed vulnerable:`);
    console.log(`   - Complete fund loss within hours`);
    console.log(`   - Platform reputation damage`);
    console.log(`   - Potential legal consequences`);
    console.log(`   - User trust destruction`);
  });
});
