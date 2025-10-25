import { describe, it, beforeEach } from "node:test";
import assert from "node:assert";
import { network } from "hardhat";
import { Address, parseEther, getAddress } from "viem";

describe("DZNFT Token Transfer Tests", async function () {
  const { viem, networkHelpers } = await network.connect();
  const publicClient = await viem.getPublicClient();

  let dznft: any;
  let fundraisingContract: any;
  let mockUSDT: any;
  let owner: Address;
  let investor1: Address;
  let investor2: Address;

  beforeEach(async () => {
    // Get test accounts
    const [ownerAccount, investor1Account, investor2Account] =
      await viem.getWalletClients();
    owner = ownerAccount.account.address;
    investor1 = investor1Account.account.address;
    investor2 = investor2Account.account.address;

    // Deploy MockUSDT
    mockUSDT = await viem.deployContract("MockUSDT", [
      "Mock USDT",
      "USDT",
      18,
      parseEther("1000000"), // 1M USDT
    ]);

    // Deploy DZNFT
    dznft = await viem.deployContract("DZNFT", []);

    // Deploy FundRaisingContractNFT
    fundraisingContract = await viem.deployContract("FundRaisingContractNFT", [
      dznft.address,
      mockUSDT.address,
    ]);

    // Grant EXECUTOR_ROLE to fundraising contract
    const executorRole = await dznft.read.EXECUTOR_ROLE();
    await dznft.write.grantRole([executorRole, fundraisingContract.address]);

    // Transfer some USDT to investors
    await mockUSDT.write.transfer([investor1, parseEther("10000")]);
    await mockUSDT.write.transfer([investor2, parseEther("10000")]);

    // Approve fundraising contract to spend USDT
    await mockUSDT.write.approve(
      [fundraisingContract.address, parseEther("10000")],
      {
        account: investor1,
      }
    );
    await mockUSDT.write.approve(
      [fundraisingContract.address, parseEther("10000")],
      {
        account: investor2,
      }
    );
  });

  describe("Basic Token Transfer Tests", () => {
    it("should allow normal transfers when not locked", async () => {
      // Create investment round
      const currentTime = Math.floor(Date.now() / 1000);
      const closeDate = currentTime + 30 * 24 * 60 * 60; // 30 days
      const endDate = closeDate + 365 * 24 * 60 * 60; // 365 days after close

      await fundraisingContract.write.createInvestmentRound([
        "Test Round",
        10, // $10 per token
        600, // 6% reward
        1000, // 1000 tokens available
        closeDate,
        endDate,
      ]);

      // Investor1 buys 1 NFT
      await fundraisingContract.write.investInRound([0, 1], {
        account: investor1,
      });

      // Check NFT ownership
      const tokenId = 0;
      const owner = await dznft.read.ownerOf([tokenId]);
      assert.strictEqual(owner.toLowerCase(), investor1.toLowerCase());

      // Check transfer is not locked initially
      const isLocked = await dznft.read.isTransferLocked([tokenId]);
      assert.strictEqual(isLocked, false);

      // Transfer should work
      await dznft.write.transferFrom([investor1, investor2, tokenId], {
        account: investor1,
      });

      // Check new ownership
      const newOwner = await dznft.read.ownerOf([tokenId]);
      assert.strictEqual(newOwner.toLowerCase(), investor2.toLowerCase());
    });

    it("should allow safe transfers when not locked", async () => {
      // Create investment round
      const currentTime = Math.floor(Date.now() / 1000);
      const closeDate = currentTime + 30 * 24 * 60 * 60;
      const endDate = closeDate + 365 * 24 * 60 * 60;

      await fundraisingContract.write.createInvestmentRound([
        "Test Round",
        10,
        600,
        1000,
        closeDate,
        endDate,
      ]);

      // Investor1 buys 1 NFT
      await fundraisingContract.write.investInRound([0, 1], {
        account: investor1,
      });

      const tokenId = 0;

      // Safe transfer should work
      await dznft.write.safeTransferFrom([investor1, investor2, tokenId], {
        account: investor1,
      });

      // Check new ownership
      const newOwner = await dznft.read.ownerOf([tokenId]);
      assert.strictEqual(newOwner.toLowerCase(), investor2.toLowerCase());
    });
  });

  describe("Transfer Lock Tests", () => {
    let tokenId: number;

    beforeEach(async () => {
      // Create investment round
      const currentTime = Math.floor(Date.now() / 1000);
      const closeDate = currentTime + 30 * 24 * 60 * 60;
      const endDate = closeDate + 365 * 24 * 60 * 60;

      await fundraisingContract.write.createInvestmentRound([
        "Test Round",
        10,
        600,
        1000,
        closeDate,
        endDate,
      ]);

      // Investor1 buys 1 NFT
      await fundraisingContract.write.investInRound([0, 1], {
        account: investor1,
      });

      tokenId = 0;
    });

    it("should block transfers when token is locked", async () => {
      // Lock the token
      await dznft.write.lockTransfer([tokenId]);

      // Check transfer is locked
      const isLocked = await dznft.read.isTransferLocked([tokenId]);
      assert.strictEqual(isLocked, true);

      // Transfer should fail
      try {
        await dznft.write.transferFrom([investor1, investor2, tokenId], {
          account: investor1,
        });
        assert.fail("Transfer should have failed");
      } catch (error: any) {
        assert(error.message.includes("Token transfer locked"));
      }
    });

    it("should block safe transfers when token is locked", async () => {
      // Lock the token
      await dznft.write.lockTransfer([tokenId]);

      // Safe transfer should fail
      try {
        await dznft.write.safeTransferFrom([investor1, investor2, tokenId], {
          account: investor1,
        });
        assert.fail("Safe transfer should have failed");
      } catch (error: any) {
        assert(error.message.includes("Token transfer locked"));
      }
    });

    it("should allow transfers after unlocking", async () => {
      // Lock the token
      await dznft.write.lockTransfer([tokenId]);

      // Verify it's locked
      let isLocked = await dznft.read.isTransferLocked([tokenId]);
      assert.strictEqual(isLocked, true);

      // For testing purposes, we need to mark as redeemed first to unlock
      // In real scenario, this would happen through the claim process
      await dznft.write.markAsRedeemed([tokenId]);

      // Unlock the token
      await dznft.write.unlockTransfer([tokenId]);

      // Verify it's unlocked
      isLocked = await dznft.read.isTransferLocked([tokenId]);
      assert.strictEqual(isLocked, false);

      // Transfer should work now
      await dznft.write.transferFrom([investor1, investor2, tokenId], {
        account: investor1,
      });

      // Check new ownership
      const newOwner = await dznft.read.ownerOf([tokenId]);
      assert.strictEqual(newOwner.toLowerCase(), investor2.toLowerCase());
    });

    it("should only allow executor to lock/unlock transfers", async () => {
      // Check that investor1 does NOT have executor role
      const hasExecutorRole = await dznft.read.isExecutor([investor1]);
      assert.strictEqual(
        hasExecutorRole,
        false,
        "investor1 should not have executor role"
      );

      // Non-executor should not be able to lock
      let errorOccurred = false;
      try {
        await dznft.write.lockTransfer([tokenId], {
          account: investor1,
        });
      } catch (error: any) {
        errorOccurred = true;
        assert(
          error.message.includes("Caller is not an executor") ||
            error.message.includes("AccessControl") ||
            error.message.includes("EXECUTOR_ROLE")
        );
      }
      assert.strictEqual(
        errorOccurred,
        true,
        "Non-executor should not be able to lock transfers"
      );

      // Lock as owner (who has executor role) first for unlock test
      await dznft.write.lockTransfer([tokenId]);
      await dznft.write.markAsRedeemed([tokenId]); // Mark as redeemed to allow unlock

      // Non-executor should not be able to unlock
      errorOccurred = false;
      try {
        await dznft.write.unlockTransfer([tokenId], {
          account: investor1,
        });
      } catch (error: any) {
        errorOccurred = true;
        assert(
          error.message.includes("Caller is not an executor") ||
            error.message.includes("AccessControl") ||
            error.message.includes("EXECUTOR_ROLE")
        );
      }
      assert.strictEqual(
        errorOccurred,
        true,
        "Non-executor should not be able to unlock transfers"
      );

      // Owner (executor) should be able to unlock
      await dznft.write.unlockTransfer([tokenId]); // This should work
      const isLocked = await dznft.read.isTransferLocked([tokenId]);
      assert.strictEqual(isLocked, false, "Owner should be able to unlock");
    });
  });

  describe("Approval Tests with Transfer Lock", () => {
    let tokenId: number;

    beforeEach(async () => {
      // Create investment round and mint NFT
      const currentTime = Math.floor(Date.now() / 1000);
      const closeDate = currentTime + 30 * 24 * 60 * 60;
      const endDate = closeDate + 365 * 24 * 60 * 60;

      await fundraisingContract.write.createInvestmentRound([
        "Test Round",
        10,
        600,
        1000,
        closeDate,
        endDate,
      ]);

      await fundraisingContract.write.investInRound([0, 1], {
        account: investor1,
      });

      tokenId = 0;
    });

    it("should allow approval when token is not locked", async () => {
      // Approve investor2 to transfer the token
      await dznft.write.approve([investor2, tokenId], {
        account: investor1,
      });

      // Check approval
      const approved = await dznft.read.getApproved([tokenId]);
      assert.strictEqual(approved.toLowerCase(), investor2.toLowerCase());

      // Approved address should be able to transfer
      await dznft.write.transferFrom([investor1, investor2, tokenId], {
        account: investor2,
      });

      const newOwner = await dznft.read.ownerOf([tokenId]);
      assert.strictEqual(newOwner.toLowerCase(), investor2.toLowerCase());
    });

    it("should block transfers by approved address when token is locked", async () => {
      // Approve investor2 first
      await dznft.write.approve([investor2, tokenId], {
        account: investor1,
      });

      // Lock the token
      await dznft.write.lockTransfer([tokenId]);

      // Approved address should not be able to transfer locked token
      try {
        await dznft.write.transferFrom([investor1, investor2, tokenId], {
          account: investor2,
        });
        assert.fail(
          "Approved address should not be able to transfer locked token"
        );
      } catch (error: any) {
        assert(error.message.includes("Token transfer locked"));
      }
    });
  });

  describe("Batch Transfer Tests", () => {
    it("should handle multiple NFT transfers correctly", async () => {
      // Create investment round
      const currentTime = Math.floor(Date.now() / 1000);
      const closeDate = currentTime + 30 * 24 * 60 * 60;
      const endDate = closeDate + 365 * 24 * 60 * 60;

      await fundraisingContract.write.createInvestmentRound([
        "Test Round",
        10,
        600,
        1000,
        closeDate,
        endDate,
      ]);

      // Investor1 buys 3 NFTs
      await fundraisingContract.write.investInRound([0, 3], {
        account: investor1,
      });

      // Check ownership of all three tokens
      for (let i = 0; i < 3; i++) {
        const owner = await dznft.read.ownerOf([i]);
        assert.strictEqual(owner.toLowerCase(), investor1.toLowerCase());
      }

      // Transfer each token individually
      for (let i = 0; i < 3; i++) {
        await dznft.write.transferFrom([investor1, investor2, i], {
          account: investor1,
        });

        const newOwner = await dznft.read.ownerOf([i]);
        assert.strictEqual(newOwner.toLowerCase(), investor2.toLowerCase());
      }
    });

    it("should handle mixed locked/unlocked tokens correctly", async () => {
      // Create investment round
      const currentTime = Math.floor(Date.now() / 1000);
      const closeDate = currentTime + 30 * 24 * 60 * 60;
      const endDate = closeDate + 365 * 24 * 60 * 60;

      await fundraisingContract.write.createInvestmentRound([
        "Test Round",
        10,
        600,
        1000,
        closeDate,
        endDate,
      ]);

      // Investor1 buys 2 NFTs
      await fundraisingContract.write.investInRound([0, 2], {
        account: investor1,
      });

      // Lock only the first token
      await dznft.write.lockTransfer([0]);

      // Transfer of locked token should fail
      try {
        await dznft.write.transferFrom([investor1, investor2, 0], {
          account: investor1,
        });
        assert.fail("Transfer of locked token should fail");
      } catch (error: any) {
        assert(error.message.includes("Token transfer locked"));
      }

      // Transfer of unlocked token should succeed
      await dznft.write.transferFrom([investor1, investor2, 1], {
        account: investor1,
      });

      const owner0 = await dznft.read.ownerOf([0]);
      const owner1 = await dznft.read.ownerOf([1]);

      assert.strictEqual(owner0.toLowerCase(), investor1.toLowerCase()); // Still with investor1
      assert.strictEqual(owner1.toLowerCase(), investor2.toLowerCase()); // Transferred to investor2
    });
  });

  describe("Pause Functionality Tests", () => {
    let tokenId: number;

    beforeEach(async () => {
      // Create investment round and mint NFT
      const currentTime = Math.floor(Date.now() / 1000);
      const closeDate = currentTime + 30 * 24 * 60 * 60;
      const endDate = closeDate + 365 * 24 * 60 * 60;

      await fundraisingContract.write.createInvestmentRound([
        "Test Round",
        10,
        600,
        1000,
        closeDate,
        endDate,
      ]);

      await fundraisingContract.write.investInRound([0, 1], {
        account: investor1,
      });

      tokenId = 0;
    });

    it("should block all transfers when contract is paused", async () => {
      // Pause the contract
      await dznft.write.pause();

      // Transfer should fail when paused
      try {
        await dznft.write.transferFrom([investor1, investor2, tokenId], {
          account: investor1,
        });
        assert.fail("Transfer should fail when contract is paused");
      } catch (error: any) {
        assert(error.message.includes("Token transfer while paused"));
      }
    });

    it("should allow transfers after unpausing", async () => {
      // Pause then unpause
      await dznft.write.pause();
      await dznft.write.unpause();

      // Transfer should work after unpausing
      await dznft.write.transferFrom([investor1, investor2, tokenId], {
        account: investor1,
      });

      const newOwner = await dznft.read.ownerOf([tokenId]);
      assert.strictEqual(newOwner.toLowerCase(), investor2.toLowerCase());
    });
  });
});
