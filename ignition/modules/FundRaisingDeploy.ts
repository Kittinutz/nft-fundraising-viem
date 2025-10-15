import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
export default buildModule("FundRaisingContractNFT", (m) => {
  const dzNft = m.contract("DZNFT");
  const usdt = m.contract("MockUSDT", [
    "Mock USDT",
    "MUSDT",
    18n,
    1_000_000_000n,
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
    Date.now() + 30 * 24 * 60 * 60 * 1000,
    Date.now() + 365 * 24 * 60 * 60 * 1000,
  ]);

  return { fundRaisingContractNFT };
});
