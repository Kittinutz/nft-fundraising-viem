import { network } from "hardhat";

async function main() {
  const { viem, networkHelpers } = await network.connect();
  const [wallet1, wallet2, wallet3] = await viem.getWalletClients();

  const coreContract = await viem.getContractAt(
    "FundRaisingCore",
    "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"
  );
  const usdt = await viem.getContractAt(
    "MockUSDT",
    "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"
  );
  const balanceOfCore = await usdt.read.balanceOf([coreContract.address]);
  if (balanceOfCore <= 265000n * 10n ** 18n) {
    await usdt.write.mint([wallet1.account.address, 265000n * 10n ** 18n]);
    await usdt.write.approve([coreContract.address, 265000n * 10n ** 18n]);
    await coreContract.write.addRewardToRound([1n, 265000n]);
  }
  await networkHelpers.mine();
  await networkHelpers.time.increase(60 * 60 * 24 * 30 * 7);
  await networkHelpers.mine();
  console.log("done");
}
main();
