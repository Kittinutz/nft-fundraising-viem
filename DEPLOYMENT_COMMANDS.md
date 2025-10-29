# ⚡ Deployment Command Reference

## Quick Commands

### Local Development

```bash
# Deploy to hardhat network
npx hardhat ignition deploy ./ignition/modules/FundRaisingDeploy.ts
```

### Testnet (Sepolia)

```bash
# Set environment
export SEPOLIA_RPC_URL="https://sepolia.infura.io/v3/YOUR_INFURA_KEY"
export PRIVATE_KEY="0x..."

# Deploy and verify
npx hardhat ignition deploy ./ignition/modules/FundRaisingDeploy.ts \
  --network sepolia --verify
```

### Testnet (Polygon Mumbai)

```bash
# Set environment
export MUMBAI_RPC_URL="https://rpc-mumbai.maticvigil.com"
export PRIVATE_KEY="0x..."

# Deploy and verify
npx hardhat ignition deploy ./ignition/modules/FundRaisingDeploy.ts \
  --network mumbai --verify
```

### Mainnet (Ethereum)

```bash
# Set environment
export MAINNET_RPC_URL="https://eth-mainnet.infura.io/v3/YOUR_INFURA_KEY"
export PRIVATE_KEY="0x..."
export ETHERSCAN_API_KEY="YOUR_ETHERSCAN_KEY"

# Deploy and verify
npx hardhat ignition deploy ./ignition/modules/FundRaisingDeploy.ts \
  --network mainnet --verify
```

### Mainnet (Polygon)

```bash
# Set environment
export POLYGON_RPC_URL="https://polygon-rpc.com"
export PRIVATE_KEY="0x..."
export POLYGONSCAN_API_KEY="YOUR_POLYGONSCAN_KEY"

# Deploy and verify
npx hardhat ignition deploy ./ignition/modules/FundRaisingDeploy.ts \
  --network polygon --verify
```

## Verify Deployment

### Check Local Deployment

```bash
# List deployment files
ls -la ignition/deployments/chain-31337/

# View deployed addresses
cat ignition/deployments/chain-31337/deployed_addresses.json
```

### Check Testnet Deployment

```bash
# View Sepolia deployment
cat ignition/deployments/chain-11155111/deployed_addresses.json

# View on Etherscan Sepolia
# https://sepolia.etherscan.io/address/0x...
```

### Check Mainnet Deployment

```bash
# View Mainnet deployment
cat ignition/deployments/chain-1/deployed_addresses.json

# View on Etherscan
# https://etherscan.io/address/0x...
```

## Test Deployment

### Compile Before Deploy

```bash
npx hardhat compile
```

### Clean and Rebuild

```bash
npx hardhat clean
npx hardhat compile
```

### Run Tests

```bash
npx hardhat test
```

## Configuration Setup

### Create .env File

```bash
cat > .env << 'EOF'
# Network RPCs
SEPOLIA_RPC_URL="https://sepolia.infura.io/v3/YOUR_KEY"
MAINNET_RPC_URL="https://eth-mainnet.infura.io/v3/YOUR_KEY"
MUMBAI_RPC_URL="https://rpc-mumbai.maticvigil.com"
POLYGON_RPC_URL="https://polygon-rpc.com"

# Private key (NEVER commit this!)
PRIVATE_KEY="0x..."

# API Keys for verification
ETHERSCAN_API_KEY="YOUR_KEY"
POLYGONSCAN_API_KEY="YOUR_KEY"
EOF
```

### Update hardhat.config.ts

```typescript
import dotenv from "dotenv";
dotenv.config();

const config: HardhatUserConfig = {
  solidity: "0.8.28",
  networks: {
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    mainnet: {
      url: process.env.MAINNET_RPC_URL,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    polygon: {
      url: process.env.POLYGON_RPC_URL,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    mumbai: {
      url: process.env.MUMBAI_RPC_URL,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      sepolia: process.env.ETHERSCAN_API_KEY || "",
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      polygon: process.env.POLYGONSCAN_API_KEY || "",
      polygonMumbai: process.env.POLYGONSCAN_API_KEY || "",
    },
  },
};
```

## Post-Deployment

### Get Deployment Addresses

```bash
# Local
node -e "console.log(require('./ignition/deployments/chain-31337/deployed_addresses.json'))"

# Sepolia
node -e "console.log(require('./ignition/deployments/chain-11155111/deployed_addresses.json'))"

# Mainnet
node -e "console.log(require('./ignition/deployments/chain-1/deployed_addresses.json'))"
```

### Verify Single Contract

```bash
npx hardhat verify --network sepolia \
  CONTRACT_ADDRESS \
  "Constructor" "Arg1" "Arg2"
```

### Test Deployed Contract

```bash
# Check core contract
npx hardhat run --network sepolia \
  scripts/test-deployed.ts

# Example test-deployed.ts:
// import { ethers } from "hardhat";
// const coreAddress = "0x...";
// const core = await ethers.getContractAt("FundRaisingCore", coreAddress);
// const rounds = await core.getRoundCount();
// console.log("Rounds:", rounds);
```

## Troubleshooting Commands

### Check Gas Prices

```bash
# Check current gas prices on Sepolia
curl https://sepolia.infura.io/v3/YOUR_KEY \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}'
```

### Check Account Balance

```bash
# Check balance
npx hardhat run --network sepolia \
  -e "const ethers = require('ethers'); const balance = await ethers.provider.getBalance('0x...'); console.log(balance.toString());"
```

### View Account Details

```bash
# Show account info
node -e "
const ethers = require('ethers');
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY);
console.log('Address:', wallet.address);
console.log('PublicKey:', wallet.publicKey);
"
```

## Common Issues

### "No such file or directory"

```bash
# Make sure you're in the right directory
pwd
cd /path/to/nft-fundraising

# Check files exist
ls ignition/modules/FundRaisingDeploy.ts
```

### "Invalid network"

```bash
# List available networks
npx hardhat networks list

# Or check hardhat.config.ts for network definitions
```

### "Insufficient funds"

```bash
# Check balance
npx hardhat run --network sepolia scripts/check-balance.ts

# Request test funds from faucet
# Sepolia: https://sepolia-faucet.pk910.de/
# Mumbai: https://faucet.polygon.technology/
```

### "Contract not found"

```bash
# Compile first
npx hardhat compile

# Check ABIs in artifacts
ls artifacts/contracts/
```

## Backup and Restore

### Backup Deployments

```bash
# Backup deployment records
cp -r ignition/deployments ~/backup-deployments-$(date +%Y%m%d)

# Backup contract ABIs
cp -r artifacts ~/backup-artifacts-$(date +%Y%m%d)
```

### Export Addresses

```bash
# Export to JSON
node -e "
const fs = require('fs');
const addrs = require('./ignition/deployments/chain-11155111/deployed_addresses.json');
fs.writeFileSync('deployed-addresses.json', JSON.stringify(addrs, null, 2));
console.log('Exported to deployed-addresses.json');
"

# Export to CSV
node -e "
const addrs = require('./ignition/deployments/chain-11155111/deployed_addresses.json');
const csv = Object.entries(addrs[Object.keys(addrs)[0]]).map(([k,v]) => \`\${k},\${v}\`).join('\n');
console.log(csv);
" > addresses.csv
```

## Documentation

- **Comprehensive**: `IGNITION_DEPLOYMENT_GUIDE.md`
- **Quick Reference**: `DEPLOYMENT_QUICK_REFERENCE.md`
- **Validation**: `DEPLOYMENT_VALIDATION_REPORT.md`
- **Summary**: `IGNITION_FIX_SUMMARY.md`
- **Status**: `DEPLOYMENT_COMPLETE.md`

---

**Ready to Deploy!** 🚀

Use these commands to deploy your FundRaising contract suite across any network.
