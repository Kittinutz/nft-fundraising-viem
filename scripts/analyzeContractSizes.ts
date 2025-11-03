import { artifacts } from "hardhat";

async function main() {
  console.log("\n🔍 DETAILED CONTRACT SIZE ANALYSIS\n");
  console.log("═".repeat(100));

  const contracts = [
    "FundRaisingFactory",
    "FundRaisingCore",
    "FundRaisingClaims",
    "FundRaisingAdmin",
    "FundRaisingAnalytics",
    "DZNFT",
    "MockUSDT",
  ];

  const SIZE_LIMIT = 24576; // 24 KB
  let totalSize = 0;
  const results: Array<{
    name: string;
    deployedSize: number;
    creationSize: number;
    percentage: number;
    status: string;
    oversized: boolean;
  }> = [];

  console.log(
    "Contract".padEnd(25) +
      "Deployed Size".padEnd(15) +
      "Creation Size".padEnd(15) +
      "% Limit".padEnd(10) +
      "Status"
  );
  console.log("─".repeat(100));

  for (const contractName of contracts) {
    try {
      const artifact = await artifacts.readArtifact(contractName);

      const deployedSize = (artifact.deployedBytecode.length - 2) / 2;
      const creationSize = (artifact.bytecode.length - 2) / 2;
      const percentage = (deployedSize / SIZE_LIMIT) * 100;

      let status = "";
      let oversized = false;

      if (deployedSize >= SIZE_LIMIT) {
        status = "🔴 EXCEEDS LIMIT";
        oversized = true;
      } else if (percentage > 95) {
        status = "🟠 CRITICAL";
      } else if (percentage > 85) {
        status = "🟡 WARNING";
      } else if (percentage > 75) {
        status = "🟢 CAUTION";
      } else {
        status = "✅ SAFE";
      }

      results.push({
        name: contractName,
        deployedSize,
        creationSize,
        percentage,
        status,
        oversized,
      });

      totalSize += deployedSize;

      const deployedKB = (deployedSize / 1024).toFixed(2);
      const creationKB = (creationSize / 1024).toFixed(2);

      console.log(
        contractName.padEnd(25) +
          `${deployedKB} KB`.padEnd(15) +
          `${creationKB} KB`.padEnd(15) +
          `${percentage.toFixed(1)}%`.padEnd(10) +
          status
      );
    } catch (error) {
      console.log(
        `${contractName.padEnd(25)}❌ ERROR`.padEnd(54) + "COMPILE FAILED"
      );
    }
  }

  console.log("─".repeat(100));

  // Analysis
  const oversizedContracts = results.filter((r) => r.oversized);
  const criticalContracts = results.filter(
    (r) => r.percentage > 95 && !r.oversized
  );
  const warningContracts = results.filter(
    (r) => r.percentage > 85 && r.percentage <= 95
  );

  console.log(`\n📊 SIZE ANALYSIS SUMMARY:\n`);
  console.log(`Total Contracts:           ${results.length}`);
  console.log(`Combined Size:             ${(totalSize / 1024).toFixed(2)} KB`);
  console.log(
    `Average Size:              ${(totalSize / results.length / 1024).toFixed(
      2
    )} KB`
  );

  console.log(`\n🚨 CRITICAL ISSUES:\n`);
  console.log(
    `Exceeds Limit (>24 KB):    ${oversizedContracts.length} contracts`
  );
  console.log(
    `Critical Risk (95-100%):   ${criticalContracts.length} contracts`
  );
  console.log(
    `High Risk (85-95%):        ${warningContracts.length} contracts`
  );

  if (oversizedContracts.length > 0) {
    console.log(`\n🔴 OVERSIZED CONTRACTS (BLOCKING DEPLOYMENT):\n`);
    oversizedContracts.forEach((contract) => {
      const overageBytes = contract.deployedSize - SIZE_LIMIT;
      const overageKB = (overageBytes / 1024).toFixed(2);
      console.log(`  ${contract.name}:`);
      console.log(`    Size: ${(contract.deployedSize / 1024).toFixed(2)} KB`);
      console.log(`    Overage: +${overageBytes} bytes (+${overageKB} KB)`);
      console.log(`    Must reduce by: ${overageKB} KB minimum\n`);
    });
  }

  // Detailed breakdown by largest contracts
  const sortedBySize = [...results].sort(
    (a, b) => b.deployedSize - a.deployedSize
  );

  console.log(`\n📈 TOP 3 LARGEST CONTRACTS:\n`);
  for (let i = 0; i < Math.min(3, sortedBySize.length); i++) {
    const contract = sortedBySize[i];
    const remaining = SIZE_LIMIT - contract.deployedSize;

    console.log(`${i + 1}. ${contract.name}`);
    console.log(
      `   Size: ${(contract.deployedSize / 1024).toFixed(
        2
      )} KB (${contract.percentage.toFixed(1)}%)`
    );
    console.log(
      `   Remaining: ${
        remaining >= 0 ? (remaining / 1024).toFixed(2) : "EXCEEDED"
      } KB`
    );
    console.log();
  }

  return {
    oversizedCount: oversizedContracts.length,
    criticalCount: criticalContracts.length,
    warningCount: warningContracts.length,
    canDeploy: oversizedContracts.length === 0,
  };
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
