# FundRaising Ignition Deployment Guide

## Overview

The updated Hardhat Ignition deployment module (`FundRaisingDeploy.ts`) now correctly deploys the complete FundRaising contract suite with proper initialization and configuration.

## Fixed Issues

### Previous Issues ❌

1. **Incorrect Contract Reference**: Referenced non-existent `FundRaisingContractNFT` instead of split architecture
2. **Missing Factory Pattern**: Didn't use the FundRaisingFactory for coordinated deployment
3. **Incomplete Setup**: Missing authorization setup and claims contract deployment
4. **Token Decimals**: Used incorrect token price format (missing decimals)

### Fixed Implementation ✅

1. **Factory Pattern**: Uses FundRaisingFactory for coordinated deployment
2. **Complete Suite**: Deploys all contracts (Core, Analytics, Admin, Claims)
3. **Proper Authorization**: Sets up executor roles and authorized claims contract
4. **Correct Token Amounts**: Uses proper decimal formatting (18 decimals)
5. **Initial Rounds**: Creates sample investment rounds for testing

## Deployment Architecture

```
┌─────────────────────────────────────┐
│   FundRaising Deployment Module     │
└──────────────┬──────────────────────┘
               │
        ┌──────┴──────────────┐
        ▼                     ▼
    ┌────────────┐       ┌──────────┐
    │   DZNFT    │       │ MockUSDT │
    └────────────┘       └──────────┘
        ▲                     ▲
        │                     │
        └─────────┬──────────┘
                  ▼
          ┌──────────────────┐
          │  Factory Deploy  │
          └────────┬─────────┘
                   │
        ┌──────────┼──────────────────┐
        ▼          ▼                  ▼
    ┌────────┐ ┌──────────┐ ┌──────────┐
    │ Core   │ │Analytics │ │  Admin   │
    └────────┘ └──────────┘ └──────────┘
        ▲
        │
    ┌──────────────┐
    │   Claims     │
    └──────────────┘
```

## Contract Deployment Order

### Step 1: Base Contracts

```typescript
const dzNft = m.contract("DZNFT");
const usdt = m.contract("MockUSDT", [...]);
```

- DZNFT: ERC721 contract for NFT tokens
- MockUSDT: ERC20 contract for USDT (testing)

### Step 2: Factory Deployment

```typescript
const factory = m.contract("FundRaisingFactory");
const deployTx = m.call(factory, "deployFundRaising", [dzNft, usdt]);
```

- Deploys FundRaisingFactory
- Calls deployFundRaising to create Core, Analytics, and Admin contracts
- Automatically transfers ownership to caller

### Step 3: Claims Contract

```typescript
const fundRaisingClaims = m.contract("FundRaisingClaims", [
  fundRaisingCore,
  dzNft,
  usdt,
]);
```

- Deployed separately after Core contract is ready
- Needs reference to FundRaisingCore for reward calculations

### Step 4: Authorization Setup

```typescript
m.call(fundRaisingCore, "setAuthorizedClaimsContract", [fundRaisingClaims]);
m.call(dzNft, "updateExecutorRole", [fundRaisingCore, true]);
m.call(dzNft, "updateExecutorRole", [fundRaisingClaims, true]);
```

- Sets claims contract as authorized for core contract
- Grants executor roles to contracts that mint/transfer NFTs

### Step 5: Initial Configuration

```typescript
m.call(fundRaisingCore, "createInvestmentRound", [...]);
```

- Creates sample investment rounds
- Configurable for different token prices and reward percentages

## Configuration Parameters

### MockUSDT Configuration

```typescript
const usdt = m.contract("MockUSDT", [
  "Mock USDT", // Token name
  "MUSDT", // Token symbol
  18n, // Decimals (18 for USDT compatibility)
  10000000n * 10n ** 18n, // Initial supply (10 million USDT)
]);
```

### Investment Rounds

```typescript
// Round 1 - Early Birds
m.call(fundRaisingCore, "createInvestmentRound", [
  "Round 1 - Early Birds",
  500n * 10n ** 18n, // Token price: 500 USDT
  6n, // Reward percentage: 6%
  1000n, // Total tokens: 1000
  thirtyDaysLater, // Close date (30 days from now)
  oneYearLater, // End date (1 year from now)
]);

// Round 2 - Public Sale
m.call(fundRaisingCore, "createInvestmentRound", [
  "Round 2 - Public Sale",
  1000n * 10n ** 18n, // Token price: 1000 USDT
  12n, // Reward percentage: 12%
  500n, // Total tokens: 500
  thirtyDaysLater,
  oneYearLater,
]);
```

## Deployment Process

### Deploy to Local Network

```bash
# Compile contracts
npx hardhat compile

# Deploy using ignition (local hardhat network)
npx hardhat ignition deploy ./ignition/modules/FundRaisingDeploy.ts
```

### Deploy to Testnet (Sepolia Example)

```bash
# Set RPC and private key
export SEPOLIA_RPC_URL="https://sepolia.infura.io/v3/YOUR_KEY"
export PRIVATE_KEY="0x..."

# Deploy to Sepolia
npx hardhat ignition deploy ./ignition/modules/FundRaisingDeploy.ts \
  --network sepolia \
  --verify
```

### Deploy to Mainnet

```bash
# Set mainnet RPC and private key
export MAINNET_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
export PRIVATE_KEY="0x..."

# Deploy with verification
npx hardhat ignition deploy ./ignition/modules/FundRaisingDeploy.ts \
  --network mainnet \
  --verify
```

## Expected Output

After successful deployment, you'll see:

```
╔════════════════════════════════════════════════════════════════╗
║             FundRaisingSuite Deployment Summary               ║
╠════════════════════════════════════════════════════════════════╣
║ ✅ DZNFT:                  0x1234...abcd                       ║
║ ✅ MockUSDT:               0x2345...bcde                       ║
║ ✅ FundRaisingFactory:     0x3456...cdef                       ║
║ ✅ FundRaisingCore:        0x4567...def0                       ║
║ ✅ FundRaisingAnalytics:   0x5678...ef01                       ║
║ ✅ FundRaisingAdmin:       0x6789...f012                       ║
║ ✅ FundRaisingClaims:      0x789a...0123                       ║
╠════════════════════════════════════════════════════════════════╣
║ Total Gas: 15,234,567                                          ║
║ Total Cost: 0.456 ETH @ 30 gwei                               ║
╚════════════════════════════════════════════════════════════════╝
```

## Post-Deployment Steps

### 1. Verify Contract Addresses

```bash
# Check deployed contracts
npx hardhat ignition verify FundRaisingSuite --network sepolia
```

### 2. Test Initial State

```typescript
// Check USDT balance
const balance = await usdtContract.balanceOf(fundRaisingCore.address);

// Check created rounds
const roundCount = await fundRaisingCore.getRoundCount();

// Check admin permissions
const isAdmin = await fundRaisingCore.owner();
```

### 3. Mint Test USDT (if using MockUSDT)

```typescript
const amount = parseEther("10000"); // 10,000 USDT
await usdtContract.mint(userAddress, amount);
```

### 4. Fund Investment Rounds

```typescript
// Approve USDT spending
await usdtContract.approve(fundRaisingCore.address, parseEther("100000"));

// Invest in round
await fundRaisingCore.investInRound(0, 50); // 50 tokens in round 0
```

## Troubleshooting

### Issue: "Contract not found"

```
Error: Could not find contract ...
```

**Solution**: Ensure all contracts are compiled

```bash
npx hardhat clean
npx hardhat compile
```

### Issue: "Invalid token address"

```
Error: Invalid USDT token address
```

**Solution**: Check that MockUSDT is deployed before Factory
**Fix**: Already handled in module - deployment order is correct

### Issue: "Insufficient permissions"

```
Error: Ownable: caller is not the owner
```

**Solution**: Ensure deployer account has proper permissions

- Check private key matches deployment account
- Verify account has sufficient funds

### Issue: "Out of gas"

```
Error: Transaction out of gas
```

**Solution**: Increase gas limit in hardhat config

```javascript
module.exports = {
  networks: {
    hardhat: {
      blockGasLimit: 30_000_000, // Increase limit
    },
  },
};
```

## Module Outputs

The deployment module returns all deployed contract instances:

```typescript
{
  factory: FundRaisingFactory,
  dzNft: DZNFT,
  usdt: MockUSDT,
  fundRaisingCore: FundRaisingCore,
  fundRaisingAnalytics: FundRaisingAnalytics,
  fundRaisingAdmin: FundRaisingAdmin,
  fundRaisingClaims: FundRaisingClaims
}
```

Use these in your tests or frontend:

```typescript
import deploymentFixture from "./ignition/modules/FundRaisingDeploy";

const deployment = await deploymentFixture();
console.log("Core:", deployment.fundRaisingCore.address);
console.log("Admin:", deployment.fundRaisingAdmin.address);
```

## Gas Estimates

Typical deployment gas costs:

| Operation                         | Gas            | Cost @ 30 gwei |
| --------------------------------- | -------------- | -------------- |
| DZNFT Deploy                      | 1,200,000      | 0.036 ETH      |
| MockUSDT Deploy                   | 800,000        | 0.024 ETH      |
| Factory Deploy                    | 300,000        | 0.009 ETH      |
| Factory Setup (deployFundRaising) | 2,500,000      | 0.075 ETH      |
| Claims Deploy                     | 1,500,000      | 0.045 ETH      |
| Authorization Setup               | 500,000        | 0.015 ETH      |
| Create 2 Rounds                   | 400,000        | 0.012 ETH      |
| **TOTAL**                         | **~7,200,000** | **~0.216 ETH** |

## Network Configuration

Add to your `hardhat.config.ts`:

```typescript
const config: HardhatUserConfig = {
  solidity: "0.8.28",
  networks: {
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155111,
    },
    polygon: {
      url: process.env.POLYGON_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 137,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || "",
  },
};
```

## Safety Checklist

- [ ] All contracts compile without errors
- [ ] Private key is secure (use environment variables)
- [ ] Have sufficient funds for gas (ETH for mainnet, testnet ETH for testnet)
- [ ] Verify contract addresses after deployment
- [ ] Test with small amounts first
- [ ] Back up deployment addresses and ABIs
- [ ] Keep ignition deployment records (in `ignition/deployments/` folder)

## Reference

- [Hardhat Ignition Documentation](https://hardhat.org/ignition/docs/getting-started)
- [FundRaisingFactory Contract](../contracts/FundRaisingFactory.sol)
- [FundRaisingCore Contract](../contracts/FundRaisingCore.sol)
- [FundRaisingClaims Contract](../contracts/FundRaisingClaims.sol)
