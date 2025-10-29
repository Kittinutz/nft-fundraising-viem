import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("FundRaisingSuite", (m) => {
  // Deploy DZNFT contract
  const dzNft = m.contract("DZNFT");

  // Deploy MockUSDT contract (for testing)
  const usdt = m.contract("MockUSDT", [
    "Mock USDT",
    "MUSDT",
    18n,
    10000000n * 10n ** 18n, // 10 million USDT initial supply
  ]);

  // Deploy FundRaisingFactory
  const factory = m.contract("FundRaisingFactory");

  // Deploy complete fund raising suite using factory
  const deployTx = m.call(factory, "deployFundRaising", [dzNft, usdt]);

  // Extract deployed contract addresses from factory deployment
  const fundRaisingCore = m.contractAt(
    "FundRaisingCore",
    m.readEventArgument(deployTx, "FundRaisingDeployed", "coreContract")
  );

  const fundRaisingAnalytics = m.contractAt(
    "FundRaisingAnalytics",
    m.readEventArgument(deployTx, "FundRaisingDeployed", "analyticsContract")
  );

  const fundRaisingAdmin = m.contractAt(
    "FundRaisingAdmin",
    m.readEventArgument(deployTx, "FundRaisingDeployed", "adminContract")
  );

  // Deploy FundRaisingClaims contract
  const fundRaisingClaims = m.contract("FundRaisingClaims", [
    fundRaisingCore,
    dzNft,
    usdt,
  ]);

  // Set authorized claims contract in core
  m.call(fundRaisingCore, "setAuthorizedClaimsContract", [fundRaisingClaims]);

  // Grant executor roles to deployed contracts
  m.call(dzNft, "updateExecutorRole", [fundRaisingCore, true]);

  // Create initial investment rounds
  const currentTime = BigInt(Math.floor(Date.now() / 1000));
  const thirtyDaysLater = currentTime + BigInt(30 * 24 * 60 * 60);
  const oneYearLater = currentTime + BigInt(365 * 24 * 60 * 60);

  m.call(fundRaisingCore, "createInvestmentRound", [
    "Round 1 - Early Birds",
    500n * 10n ** 18n, // 500 USDT per token
    6n, // 6% reward
    1000n, // 1000 tokens available
    thirtyDaysLater, // Close date
    oneYearLater, // End date
  ]);

  m.call(
    fundRaisingCore,
    "createInvestmentRound",
    [
      "Round 2 - Public Sale",
      1000n * 10n ** 18n, // 1000 USDT per token
      12n, // 12% reward
      500n, // 500 tokens available
      thirtyDaysLater,
      oneYearLater,
    ],
    {
      id: "CreatePublicSaleRound",
    }
  );
  return {
    factory,
    dzNft,
    usdt,
    fundRaisingCore,
    fundRaisingAnalytics,
    fundRaisingAdmin,
    fundRaisingClaims,
  };
});
