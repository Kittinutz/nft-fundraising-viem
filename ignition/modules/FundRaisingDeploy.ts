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

  // Deploy complete fund raising suite using factory
  // const deployTx = m.call(factory, "deployFundRaising", [dzNft, usdt]);
  const FundRaisingCore = m.contract("FundRaisingCore", [dzNft, usdt]);
  // Extract deployed contract addresses from factory deployment

  const FundRaisingAnalytics = m.contract("FundRaisingAnalytics", [
    FundRaisingCore,
  ]);
  const FundRaisingAdmin = m.contract("FundRaisingAdmin", [FundRaisingCore]);

  // Deploy FundRaisingClaims contract
  const FundRaisingClaims = m.contract("FundRaisingClaims", [
    FundRaisingCore,
    dzNft,
    usdt,
  ]);

  // Set authorized claims contract in core
  m.call(FundRaisingCore, "setAuthorizedClaimsContract", [FundRaisingClaims]);

  // Grant executor roles to deployed contracts
  m.call(dzNft, "updateExecutorRole", [FundRaisingCore, true]);

  // Create initial investment rounds
  const currentTime = BigInt(Math.floor(Date.now() / 1000));
  const thirtyDaysLater = currentTime + BigInt(30 * 24 * 60 * 60);
  const oneYearLater = currentTime + BigInt(365 * 24 * 60 * 60);

  m.call(FundRaisingCore, "createInvestmentRound", [
    "Round 1 - Early Birds",
    500n * 10n ** 18n, // 500 USDT per token
    6n, // 6% reward
    1000n, // 1000 tokens available
    thirtyDaysLater, // Close date
    oneYearLater, // End date
  ]);

  m.call(
    FundRaisingCore,
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
    dzNft,
    usdt,
    FundRaisingCore,
    FundRaisingAnalytics,
    FundRaisingAdmin,
    FundRaisingClaims,
  };
});
