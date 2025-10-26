import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
export default buildModule("FundRaisingContractNFT", (m) => {
  const dzNft = m.contract("DZNFT");
  const usdt = m.contract("MockUSDT", [
    "Mock USDT",
    "MUSDT",
    18n,
    10000000n * 10n ** 18n,
  ]);
  const fundRaisingContractNFT = m.contract("FundRaisingContractNFT", [
    dzNft,
    usdt,
  ]);
  m.call(dzNft, "updateExecutorRole", [fundRaisingContractNFT, true]);
  m.call(fundRaisingContractNFT, "createInvestmentRound", [
    "Round 1",
    500n,
    6n,
    1000n,
    BigInt(Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60),
    BigInt(Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60),
  ]);

  return { fundRaisingContractNFT };
});
