import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
export default buildModule("FundRaisingContractNFT", (m) => {
  const dzNft = m.contract("DZNFT");
  const usdt = m.contract("MockUSDT", ["Mock USDT", "MUSDT", 18]);
  const fundRaisingContractNFT = m.contract("FundRaisingContractNFT");

  return { fundRaisingContractNFT };
});
