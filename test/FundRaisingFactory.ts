import assert from "node:assert/strict";
import { beforeEach, describe, it } from "node:test";
import { network } from "hardhat";

describe("FundRaisingFactory Tests", async function () {
  const { viem } = await network.connect();
  const [owner, user1, user2] = await viem.getWalletClients();
  let factory: any, nftContract: any, usdtContract: any;

  beforeEach(async function () {
    // Deploy DZNFT
    const nft = await viem.deployContract("DZNFT", []);
    nftContract = nft;

    // Deploy MockUSDT
    const usdt = await viem.deployContract("MockUSDT", [
      "Mock USDT",
      "MUSDT",
      18,
      1000000n * 10n ** 18n,
    ]);
    usdtContract = usdt;

    // Deploy Factory
    const factoryContract = await viem.deployContract("FundRaisingFactory", []);
    factory = factoryContract;
  });

  it("Should deploy fund raising suite successfully", async function () {
    const result = await factory.write.deployFundRaising([
      nftContract.address,
      usdtContract.address,
    ]);

    // Get the deployed contract addresses by checking deployments
    const totalDeployments = await factory.read.getTotalDeployments();
    assert(totalDeployments > 0n, "Should have deployments");

    const deployerDeployments = await factory.read.getDeploymentsByDeployer([
      owner.account.address,
    ]);
    assert(deployerDeployments.length > 0, "Owner should have deployments");

    const coreAddress = deployerDeployments[deployerDeployments.length - 1];

    assert(
      coreAddress !== "0x0000000000000000000000000000000000000000",
      "Core address should be valid"
    );

    // Verify deployment info
    const deploymentInfo = await factory.read.getDeploymentInfo([coreAddress]);

    assert.equal(
      deploymentInfo.deployer.toLowerCase(),
      owner.account.address.toLowerCase()
    );
    assert.equal(deploymentInfo.active, true);
    assert.equal(
      deploymentInfo.coreContract.toLowerCase(),
      coreAddress.toLowerCase()
    );

    // Verify analytics and admin contract addresses are also valid
    assert(
      deploymentInfo.analyticsContract !==
        "0x0000000000000000000000000000000000000000",
      "Analytics address should be valid"
    );
    assert(
      deploymentInfo.adminContract !==
        "0x0000000000000000000000000000000000000000",
      "Admin address should be valid"
    );
  });

  it("Should track deployments correctly", async function () {
    // Deploy first suite
    await factory.write.deployFundRaising([
      nftContract.address,
      usdtContract.address,
    ]);

    // Deploy second suite with different user
    const factoryUser1 = await viem.getContractAt(
      "FundRaisingFactory",
      factory.address,
      {
        client: { wallet: user1 },
      }
    );

    await factoryUser1.write.deployFundRaising([
      nftContract.address,
      usdtContract.address,
    ]);

    // Check total deployments
    const totalDeployments = await factory.read.getTotalDeployments();
    assert.equal(totalDeployments, 2n);

    // Check deployments by deployer
    const ownerDeployments = await factory.read.getDeploymentsByDeployer([
      owner.account.address,
    ]);
    assert.equal(ownerDeployments.length, 1);

    const user1Deployments = await factory.read.getDeploymentsByDeployer([
      user1.account.address,
    ]);
    assert.equal(user1Deployments.length, 1);

    // Verify the deployment addresses are valid
    assert(
      ownerDeployments[0] !== "0x0000000000000000000000000000000000000000",
      "Owner deployment should be valid"
    );
    assert(
      user1Deployments[0] !== "0x0000000000000000000000000000000000000000",
      "User1 deployment should be valid"
    );
  });

  it("Should provide deployment statistics", async function () {
    // Deploy multiple suites
    await factory.write.deployFundRaising([
      nftContract.address,
      usdtContract.address,
    ]);
    await factory.write.deployFundRaising([
      nftContract.address,
      usdtContract.address,
    ]);

    const factoryUser1 = await viem.getContractAt(
      "FundRaisingFactory",
      factory.address,
      {
        client: { wallet: user1 },
      }
    );
    await factoryUser1.write.deployFundRaising([
      nftContract.address,
      usdtContract.address,
    ]);

    // Get deployment stats
    const [
      totalDeployments,
      activeDeployments,
      deploymentsFunded,
      recentDeployments,
    ] = await factory.read.getDeploymentStats();

    assert.equal(totalDeployments, 3n);
    assert.equal(activeDeployments, 3n);
    assert.equal(deploymentsFunded, 0n); // No funding yet
    assert.equal(recentDeployments.length, 3); // Should return all 3 recent deployments
  });

  it("Should allow owner to manage deployment status", async function () {
    await factory.write.deployFundRaising([
      nftContract.address,
      usdtContract.address,
    ]);

    // Get the deployed contract address
    const deployerDeployments = await factory.read.getDeploymentsByDeployer([
      owner.account.address,
    ]);
    assert(deployerDeployments.length > 0, "Should have deployments");
    const coreAddress = deployerDeployments[deployerDeployments.length - 1];

    // Initially should be active
    let deploymentInfo = await factory.read.getDeploymentInfo([coreAddress]);
    assert.equal(deploymentInfo.active, true);

    // Factory owner deactivates deployment
    await factory.write.setDeploymentStatus([coreAddress, false]);

    deploymentInfo = await factory.read.getDeploymentInfo([coreAddress]);
    assert.equal(deploymentInfo.active, false);

    // Check active count
    const activeCount = await factory.read.getActiveDeploymentsCount();
    assert.equal(activeCount, 0n);
  });

  it("Should integrate with deployed contracts", async function () {
    // Deploy suite
    await factory.write.deployFundRaising([
      nftContract.address,
      usdtContract.address,
    ]);

    // Get deployed addresses
    const deployerDeployments = await factory.read.getDeploymentsByDeployer([
      owner.account.address,
    ]);
    assert(deployerDeployments.length > 0, "Should have deployments");
    const coreAddress = deployerDeployments[deployerDeployments.length - 1];

    const deploymentInfo = await factory.read.getDeploymentInfo([coreAddress]);
    const analyticsAddress = deploymentInfo.analyticsContract;
    const adminAddress = deploymentInfo.adminContract;

    // Grant executor role to core contract
    await nftContract.write.updateExecutorRole([coreAddress, true]);

    // Get contract instances
    const coreContract = await viem.getContractAt(
      "FundRaisingCore",
      coreAddress
    );
    const analyticsContract = await viem.getContractAt(
      "FundRaisingAnalytics",
      analyticsAddress
    );
    const adminContract = await viem.getContractAt(
      "FundRaisingAdmin",
      adminAddress
    );

    // Test core functionality with proper token price (in wei)
    await coreContract.write.createInvestmentRound([
      "Factory Test Round",
      500n * 10n ** 18n, // 500 USDT per token in wei
      6n,
      1000n,
      BigInt(Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60),
      BigInt(Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60),
    ]);

    // Test analytics functionality
    const roundsCount = (await analyticsContract.read.getRoundsCount()) as [
      bigint,
      bigint
    ];
    const totalRounds = roundsCount[0];
    const activeRounds = roundsCount[1];
    assert.equal(totalRounds, 1n);
    assert.equal(activeRounds, 1n);

    // Test admin functionality
    const adminStats = (await adminContract.read.getAdminStats()) as [
      bigint,
      bigint,
      bigint,
      string
    ];
    const adminTotalRounds = adminStats[0];
    const totalUSDTRaised = adminStats[1];
    assert.equal(adminTotalRounds, 1n);
    assert.equal(totalUSDTRaised, 0n); // No investments yet

    console.log("✅ Factory deployment and integration successful!");
  });

  it("Should handle edge cases", async function () {
    // Test with invalid addresses
    let failed = false;
    try {
      await factory.write.deployFundRaising([
        "0x0000000000000000000000000000000000000000", // Invalid DZNFT
        usdtContract.address,
      ]);
    } catch (error) {
      failed = true;
    }
    assert.equal(failed, true, "Should fail with invalid DZNFT address");

    // Test getting info for non-existent deployment
    const nonExistentInfo = await factory.read.getDeploymentInfo([
      "0x1234567890123456789012345678901234567890",
    ]);
    assert.equal(
      nonExistentInfo.coreContract,
      "0x0000000000000000000000000000000000000000"
    );

    // Test getting deployments for address with no deployments
    const noDeployments = await factory.read.getDeploymentsByDeployer([
      user2.account.address,
    ]);
    assert.equal(noDeployments.length, 0);
  });
});
